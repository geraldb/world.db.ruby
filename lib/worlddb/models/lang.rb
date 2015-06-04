# encoding: utf-8

module WorldDb
  module Model

class Lang < ActiveRecord::Base
    
  has_many :usages  # join table for countries_langs
    
  has_many :countries, :through => :usages

  validates :key, format: { with: /#{LANG_KEY_PATTERN}/, message: LANG_KEY_PATTERN_MESSAGE }

  ## begin compat
  def title()       name;              end
  def title=(value) self.name = value; end
  ## end


end  # class Lang

  end # module Model
end # module WorldDb

