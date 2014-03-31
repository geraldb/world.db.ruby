# encoding: utf-8

module WorldDb
  module Model

###
##  Todo:
##  use four classes instead of one ?
#    e.g. Use class class Metro n class City n class District n class CityBase ?? - why? why not?
#
#  find a better name for CityBase ??
#     Locality ??
#      or CityCore or CityStd or CityAll or CityGeneric
#      or CityLike or CityTable or CityTbl or ???

class City < ActiveRecord::Base
  
  extend TextUtils::TagHelper  # will add self.find_tags, self.find_tags_in_attribs!, etc.

  # NB: use extend - is_<type>? become class methods e.g. self.is_<type>? for use in
  #   self.create_or_update_from_values
  extend TextUtils::ValueHelper  # e.g. self.is_year?, self.is_region?, self.is_address?, self.is_taglist? etc.


  self.table_name = 'cities'

  belongs_to :place,   class_name: 'Place',   foreign_key: 'place_id'
  belongs_to :country, class_name: 'Country', foreign_key: 'country_id'
  belongs_to :region,  class_name: 'Region',  foreign_key: 'region_id'

  ## self referencing hierachy within cities e.g. m|metro > c|city > d|district

  ## fix: use condition check for m|d|c flag?? why? why not? (NB: flags are NOT exclusive e.g. possible metro|city)
  
  ## (1) metro - level up
  has_many   :cities,    class_name: 'City',  foreign_key: 'city_id'

  ## (2) city
  belongs_to :metro,     class_name: 'City',  foreign_key: 'city_id'   ## for now alias for parent - use parent?
  has_many   :districts, class_name: 'City',  foreign_key: 'city_id'   ## for now alias for cities - use cities?

  ## (3) district - level down
  belongs_to :city,      class_name: 'City',  foreign_key: 'city_id'  ## for now alias for parent - use parent?

  has_many_tags

  ###
  #  NB: use is_  for flags to avoid conflict w/ assocs (e.g. metro?, city? etc.)
  
  def is_metro?()    m? == true;  end
  def is_city?()     c? == true;  end
  def is_district?() d? == true;  end

  before_create :on_create
  before_update :on_update

  def on_create
    place_rec = Place.create!( name: name, kind: place_kind )
    self.place_id = place_rec.id 
  end

  def on_update
    ## fix/todo: check - if name or kind changed - only update if changed ?? why? why not??
    place.update_attributes!( name: name, kind: place_kind )
  end

  def place_kind   # use place_kind_of_code ??
    ### fix/todo: make sure city records won't overlap (e.g. using metro n city flag at the same time; use separate records)
#//////////////////////////////////
#// fix: add nested record syntax e.g. city w/ metro population
#//  use (metro: 4444)  e.g. must start with (<nested_type>: props) !!! or similar
#//
    if is_metro?
      'MTRO'
    elsif is_district?
      'DIST'
    else
      'CITY'
    end
  end


  validates :key,  format: { with: /#{CITY_KEY_PATTERN}/, message: CITY_KEY_PATTERN_MESSAGE }
  validates :code, format: { with: /#{CITY_CODE_PATTERN}/, message: CITY_CODE_PATTERN_MESSAGE }, allow_nil: true


  scope :by_key,   ->{ order( 'key asc' )  }  # order by key (a-z)
  scope :by_name,  ->{ order( 'name asc' ) } # order by title (a-z)
  scope :by_pop,   ->{ order( 'pop desc' ) }  # order by pop(ulation)
  scope :by_popm,  ->{ order( 'popm desc' ) } # order by pop(ulation) metropolitan area
  scope :by_area,  ->{ order( 'area desc' ) }  # order by area (in square km)


  def all_names( opts={} )
    ### fix:
    ## allow to passing in sep or separator e.g. | or other

    return name if alt_names.blank?
    
    buf = ''
    buf << name
    buf << ' | '
    buf << alt_names.split('|').join(' | ')
    buf
  end


  def self.create_or_update_from_values( values, more_attribs={} )
    ## key & title & country required

    attribs, more_values = find_key_n_title( values )
    attribs = attribs.merge( more_attribs )

    ## check for optional values
    City.create_or_update_from_attribs( attribs, more_values )
  end


  def self.create_or_update_from_titles( titles, more_attribs = {} )
    # ary of titles e.g. ['Wien', 'Graz'] etc.

    titles.each do |title|
      values = [title]
      City.create_or_update_from_values( values, more_attribs ) 
    end # each city
  end  # method create_or_update_from_titles



  def self.create_or_update_from_attribs( new_attributes, values, opts={} )
    #   attribs -> key/value pairs e.g. hash
    #   values  -> ary of string values/strings (key not yet known; might be starting of value e.g. city:wien)

    ## opts e.g. :skip_tags true|false

    ## fix: add/configure logger for ActiveRecord!!!
    logger = LogKernel::Logger.root

    value_numbers     = []
    value_tag_keys    = []
      
    ### check for "default" tags - that is, if present new_attributes[:tags] remove from hash
    value_tag_keys += find_tags_in_attribs!( new_attributes )

    new_attributes[ :c ] = true   # assume city type by default (use metro,district to change in fixture)

    ## check for optional values

    values.each_with_index do |value,index|
      if match_region_for_country( value, new_attributes[:country_id] ) do |region|
           new_attributes[ :region_id ] = region.id
         end
      elsif match_country( value ) do |country|
              new_attributes[ :country_id ] = country.id
            end
      elsif match_metro( value ) do |city|
              new_attributes[ :city_id ] = city.id
            end
      elsif match_metro_pop( value ) do |num|  # m:
              new_attributes[ :popm ] = num
              new_attributes[ :m ] = true   #  auto-mark city as m|metro too
            end
      elsif match_metro_flag( value ) do |_|  # metro(politan area)
              new_attributes[ :c ] = false   # turn off default c|city flag; make it m|metro only
              new_attributes[ :m ] = true
            end
      elsif match_city( value ) do |city|  # parent city for district
              new_attributes[ :city_id ] = city.id
              new_attributes[ :c ] = false # turn off default c|city flag; make it d|district only
              new_attributes[ :d ] = true
            end
      elsif match_km_squared( value ) do |num|   # allow numbers like 453 km²
              value_numbers << num
            end
      elsif match_number( value ) do |num|    # numeric (nb: can use any _ or spaces inside digits e.g. 1_000_000 or 1 000 000)
              value_numbers << num
            end
      elsif value =~ /#{CITY_CODE_PATTERN}/  ## assume three-letter code
        new_attributes[ :code ] = value
      elsif (values.size==(index+1)) && is_taglist?( value )   # tags must be last entry
        logger.debug "   found tags: >>#{value}<<"
        value_tag_keys += find_tags( value )
      else
        # issue warning: unknown type for value
        logger.warn "unknown type for value >#{value}<"
      end
    end # each value

    if value_numbers.size > 0
      new_attributes[ :pop  ] = value_numbers[0]   # assume first number is pop for cities
      new_attributes[ :area ] = value_numbers[1]  
    end

    rec = City.find_by_key( new_attributes[ :key ] )

    if rec.present?
      logger.debug "update City #{rec.id}-#{rec.key}:"
    else
      logger.debug "create City:"
      rec = City.new
    end

    logger.debug new_attributes.to_json

    rec.update_attributes!( new_attributes )

      ##################
      ## add taggings

      ## todo/fix: reuse - move add taggings into method etc.

      if value_tag_keys.size > 0

        if opts[:skip_tags].present?
          logger.debug "   skipping add taggings (flag skip_tag)"
        else
          value_tag_keys.uniq!  # remove duplicates
          logger.debug "   adding #{value_tag_keys.size} taggings: >>#{value_tag_keys.join('|')}<<..."

          ### fix/todo: check tag_ids and only update diff (add/remove ids)

          value_tag_keys.each do |key|
            tag = Tag.find_by_key( key )
            if tag.nil?  # create tag if it doesn't exit
              logger.debug "   creating tag >#{key}<"
              tag = Tag.create!( key: key )
            end
            rec.tags << tag
          end
        end
      end

    rec
  end # method create_or_update_from_values


end # class Cities

  end # module Model
end # module WorldDb
