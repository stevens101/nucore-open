class User < ActiveRecord::Base
  include Role

  devise :ldap_authenticatable, :database_authenticatable, :encryptable, :trackable

  #has_many :accounts, :foreign_key => :owner_user_id, :order => :account_number
  has_many :accounts, :through => :account_users
  has_many :account_users, :conditions => {:deleted_at => nil}
  has_many :orders
  has_many :order_details, :through => :orders
  has_many :price_group_members
  has_many :product_users
  has_many :products, :through => :product_users
  has_many :assigned_order_details, :class_name => 'OrderDetail', :foreign_key => 'assigned_user_id'
  has_many :user_roles, :dependent => :destroy
  has_many :facilities, :through => :user_roles

  validates_presence_of :username, :first_name, :last_name
  validates_format_of :email, :with => /^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,6}$/i
  validates_uniqueness_of :username, :email

  #
  # Gem ldap_authenticatable expects User to respond_to? :login. For us that's #username.
  alias_attribute :login, :username

  #
  # Gem ldap_authenticatable expects User to respond_to? :ldap_attributes. For us should return nil.
  attr_accessor :ldap_attributes


  # finds all user role mappings for a this user in a facility
  def facility_user_roles(facility)
    UserRole.find_all_by_facility_id_and_user_id(facility.id, id)
  end

  #
  # Returns true if the user is authenticated against nucore's  
  # user table, false if authenticated by an external system
  def authenticated_locally?
    encrypted_password.present? && password_salt.present?
  end

  #
  # Returns true if this user is external to organization, false othewise
  def external?
    username == email
  end


  def update_password(params)
    unless external?
      self.errors.add(:base, "Cannot update this user's password")
      return false
    end

    if params[:password].blank?
      self.errors.add(:password, "cannot be blank")
    end
    if params[:password] != params[:password_confirmation]
      self.errors.add(:password_confirmation, "does not match")
    end
    unless self.valid_password? params[:current_password]
      self.errors.add(:base, "Current password is incorrect")
    end
    if self.errors.empty?
      self.password = params[:password].strip
      self.save!
      self.clean_up_passwords
      return true 
    else
      return false
    end
    
    
  end
  # Find the users for a facility
  # TODO: move this to facility?
  def self.find_users_by_facility(facility)
    find_by_sql(<<-SQL)
      SELECT u.*
      FROM #{User.table_name} u
      LEFT JOIN #{UserRole.table_name} ur ON u.id=ur.user_id
      WHERE ur.facility_id = #{facility.id}
      ORDER BY LOWER(ur.role), LOWER(u.last_name), LOWER(u.first_name)
    SQL
  end

  #
  # A cart is an order. This method finds this user's order.
  # [_created_by_user_]
  #   The user that created the order we want. +self+ is
  #   inferred if left nil.
  # [_find_existing_]
  #   true if we want to look in the DB for an order to add
  #   new +OrderDetail+s to, false if we want a brand new order
  def cart(created_by_user = nil, find_existing=true)

    if find_existing
      # filter out instrument/reservation orders. Each of those requires a brand new order.
      # If any exist unordered it's because the user bailed on the reservation process.
      # Such orders should be cleaned from the DB periodically.
      oid=OrderDetail.select(:order_id).joins(:order, :product).where(
                        'orders.user_id = ? AND orders.created_by = ? AND orders.ordered_at IS NULL AND products.type != ?',
                        id, created_by_user ? created_by_user.id : id, Instrument.name
                      ).group(:order_id).first

      @order = Order.find(oid.order_id) if oid
    end

    @order = Order.create(:user => self, :created_by => created_by_user ? created_by_user.id : id) unless @order
    @order
  end

  def price_groups
    groups = price_group_members.collect{ |pgm| pgm.price_group }
    # check internal/external membership
    groups << (self.username.match(/@/) ? PriceGroup.external.first : PriceGroup.base.first)
    groups.flatten.uniq
  end
  
  def account_price_groups
    groups = self.accounts.active.collect{ |a| a.price_groups }.flatten.uniq
  end

  def full_name
    unless first_name.nil? and last_name.nil?
      full = ""
      full += first_name unless first_name.nil?
      full += " " unless first_name.nil? || last_name.nil?
      full += last_name unless last_name.nil?
      full
    else
      username
    end
  end

  def to_s
    full_name
  end
end
