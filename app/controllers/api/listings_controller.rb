class Api::ListingsController < Api::ApiController

  before_filter :authenticate_person!, :except => [:index, :show]
  # TODO limit visibility of listings in index method based on the visibility rules
  # It requires to authenticate the user but also allow unauthenticated access to above methods
  
  # TODO: limit the visibility of one listing. The below doesn't work yet as the param name is different in this case (only id)
  #before_filter :ensure_authorized_to_view_listing, :only => [:show]
  
  def index
    @page = params["page"] || 1
    @per_page = params["per_page"] || 50
    
    query = params.slice("category", "listing_type")
    
    unless @current_community
      response.status = 400
      render :json => ["Community_id is a required parameter."] and return
    end
    
    if params["status"] == "closed"
      query["open"] = false
    elsif params["status"] == "all"
      # leave "open" out totally to return all statuses
    else
      query["open"] = true #default
    end
    
    if params["search"]
      @listings = search_listings(params["search"], query)
    elsif params["community_id"]
      @listings = Community.find(params["community_id"]).listings.where(query).order("created_at DESC").paginate(:per_page => @per_page, :page => @page)
    else
      # This is actually not currently supported. Community_id is currently required parameter.
      @listings = Listing.where(query).order("created_at DESC").paginate(:per_page => @per_page, :page => @page)
    end
    
    @total_pages = @listings.total_pages
    respond_with @listings
  end

  def show
    @listing = Listing.find_by_id(params[:id])
    if @listing.nil?
      response.status = 404
      render :json => ["No listing found with given ID"] and return
    end
    respond_with @listing
  end

  def create
    # Set locations correctly if provided in params
    if params["latitude"] || params["address"]
      params.merge!({"origin_loc_attributes" => {"latitude" => params["latitude"], 
                                                 "longitude" => params["longitude"], 
                                                 "address" => params["address"], 
                                                 "google_address" => params["address"], 
                                                 "location_type" => "origin_loc"}})
      
      if params["destination_latitude"] || params["destination_address"]
        params.merge!({"destination_loc_attributes" => {"latitude" => params["destination_latitude"], 
                                                        "longitude" => params["destination_longitude"], 
                                                        "address" => params["destination_address"], 
                                                        "google_address" => params["destination_address"], 
                                                        "location_type" => "destination_loc"}})
      end
    end
    
    
    @listing = Listing.new(params.slice("title", 
                                        "description", 
                                        "category", 
                                        "share_type", 
                                        "listing_type", 
                                        "visibility",
                                        "origin",
                                        "destination",
                                        "origin_loc_attributes",
                                        "valid_until",
                                        "destination_loc_attributes"
                                        ).merge({"author_id" => current_person.id, 
                                                 "listing_images_attributes" => {"0" => {"image" => params["image"]} }}))
    
    @community = Community.find(params["community_id"])
    if @community.nil?
      response.status = 400
      render :json => ["community_id parameter missing, or no community found with given id"] and return
    end
    
    if current_person.member_of?(@community)
      @listing.communities << @community
    else
      response.status = 400
      render :json => ["The user is not member of given community."] and return
    end
    
    if @listing.save
      Delayed::Job.enqueue(ListingCreatedJob.new(@listing.id, @community.full_domain))
      response.status = 201 
      respond_with(@listing)
    else
      response.status = 400
      render :json => @listing.errors.full_messages and return
    end
    
  end
  
  def search_listings(search, attributes)
    with = {}
    
    unless attributes["open"].nil?
      with[:open] = true if attributes["open"] == true
      with[:open] = false if attributes["open"] == false
    end
    
    if attributes["listing_type"]
      with[:is_request] = true if attributes["listing_type"].eql?("request")
      with[:is_offer] = true if attributes["listing_type"].eql?("offer")
    end
    
    
    
    unless @current_user && @current_user.communities.include?(@current_community)
      with[:visible_to_everybody] = true
    end
    
    # Here is expected that @current_community always exists as community_id is currently required parameter
    with[:community_ids] = @current_community.id

    Listing.search(search, :include => :listing_images, 
                           :page => @page,
                           :per_page => @per_page, 
                           :star => true,
                           :with => with
                           )
  end

end