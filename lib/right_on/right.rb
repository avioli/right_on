class Right < ActiveRecord::Base

  has_and_belongs_to_many :roles

  validates_presence_of :name
  validates_uniqueness_of :name

  named_scope :ordered, :order => 'name'

  after_save :clear_cache
  after_destroy :clear_cache

  attr_accessor :group

  class << self
    @@restricted_by_right_groups = {}

    def associate_group(klass, group)
      @@restricted_by_right_groups[klass] = group
      has_one klass.table_name.singularize, :dependent => :raise
    end

    def associated_groups
      @@restricted_by_right_groups
    end

    def rights_yaml(file_path)
      @@rights_yaml = file_path
    end

    def by_groups
      rights = []
      rights += regular_rights_with_group
      rights += restricted_rights_with_group
      rights.group_by(&:group)
    end

    def regular_rights_with_group
      yaml = YAML::load_file(@@rights_yaml)
      rights = []
      rights_by_name = Hash[Right.all.map{|r| [r.name, r]}]
      yaml['rights'].each_pair do |group, right_names|
        rights_for_group = []
        right_names.each do |right_name|
          if right_name.is_a?(String) # controller
            r = rights_by_name[right_name]
            raise right_name if r.nil?
            rights_for_group << r
          else right_name.is_a?(Hash) # controller + actions
            controller, actions = right_name.first
            r = rights_by_name[controller]
            raise right_name.inspect if r.nil?
            rights_for_group << r
            actions.each do |action|
              name = "#{controller}##{action}"
              r = rights_by_name[name]
              raise name.inspect + "****" + right_name.inspect + '---' + action_right.inspect if r.nil?
              rights_for_group << r
            end
          end
        end
        rights_for_group.each{|r| r.group = group}
        rights += rights_for_group
      end
      rights
    end

    def restricted_rights_with_group
      rights = []
      @@restricted_by_right_groups.each_pair do |klass, group|
        rights += klass.all.map(&:right).each do |right|
          right.group = group
        end
      end
      rights
    end
  end

  # Is this right allowed for the given context?
  #
  # Context params is an option hash:
  #   :controller => controller name
  #   :action     => action name
  #
  # The context tells us the state of the request being made.

  def allowed?(context={})
    if controller == context[:controller]
      if action
        action_permitted?(context[:action])
      else
        # right without action works if no specific right exists
        # e.g. can't edit if there's a edit or change right defined
        # as you must used that specific right
        specific_rights = Array(APPLICABLE_RIGHTS[context[:action].to_sym]) + [context[:action]]
        specific_rights.all?{|action| Right["#{context[:controller]}##{action}"].nil?}
      end
    end
  end

  APPLICABLE_RIGHTS = {
    :new     => [:change],
    :edit    => [:change],
    :update  => [:change],
    :create  => [:change],
    :destroy => [:change],
    :index   => [:change, :view],
    :show    => [:change, :view]
  }

  CHANGE_ACTIONS = %w(new edit update create destroy index show)

  VIEW_ACTIONS = %w(index show)

  def action_permitted?(context_action)
    case action.to_sym
    when :change
      CHANGE_ACTIONS.include?(context_action)
    when :view
      VIEW_ACTIONS.include?(context_action)
    else
      action == context_action
    end
  end

  def sensible_name
    name.humanize.titleize.gsub(/#/, ' - ')
  end

  def to_s
    name
  end

  def self.cache
    Rails.cache
  end

  def self.clear_cache
    cache.delete('Right.all')
  end

  def clear_cache
    self.class.clear_cache
  end

  attr_accessor :rights
  def self.[](name)
    @rights = cache.read('Right.all') ||
      (right_cache = Hash[Right.all.map{|r|[r.name, r.id]}]) &&
      cache.write('Right.all', right_cache) &&
      right_cache
    @rights[name]
  end

end
