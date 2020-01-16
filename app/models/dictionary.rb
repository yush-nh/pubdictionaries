require 'simstring'

class Dictionary < ApplicationRecord
  include StringManipulator

  belongs_to :user
  has_many :associations
  has_many :associated_managers, through: :associations, source: :user
  has_many :dl_associations
  has_many :languages, through: :dl_associations, source: :language
  has_many :entries, :dependent => :destroy
  has_many :jobs, :dependent => :destroy

  validates :name, presence:true, uniqueness: true
  validates :user_id, presence: true 
  validates :description, presence: true
  validates :license_url, url: {allow_blank: true}
  validates_format_of :name,                              # because of to_param overriding.
                      :with => /\A[^\.]*\z/,
                      :message => "should not contain dot!"

  SIM_STRING_DB_DIR = "db/simstring/"

  scope :mine, -> (user) {
    if user.nil?
      none
    else
      includes(:associations)
        .where('dictionaries.user_id = ? OR associations.user_id = ?', user.id, user.id)
        .references(:associations)
    end
  }

  scope :editable, -> (user) {
    if user.nil?
      none
    elsif user.admin?
    else
      includes(:associations)
        .where('dictionaries.user_id = ? OR associations.user_id = ?', user.id, user.id)
        .references(:associations)
    end
  }

  scope :administrable, -> (user) {
    if user.nil?
      none
    elsif user.admin?
    else
      where('user_id = ?', user.id)
    end
  }

  class << self
    def find_dictionaries_from_params(params)
      dic_names = if params.has_key?(:dictionaries)
                   params[:dictionaries]
                 elsif params.has_key?(:dictionary)
                   params[:dictionary]
                 elsif params.has_key?(:id)
                   params[:id]
                 end
      return [] unless dic_names.present?

      dictionaries = dic_names.split(',').collect{|d| Dictionary.find_by_name(d.strip)}
      raise ArgumentError, "wrong dictionary specification." if dictionaries.include? nil

      dictionaries
    end

    def find_ids_by_labels(labels, dictionaries = [], threshold = 0.85, superfluous = false, verbose = false)
      sim_string_dbs = dictionaries.inject({}) do |h, dic|
        h[dic.name] = begin
          Simstring::Reader.new(dic.sim_string_db_path)
        rescue
          nil
        end
        if h[dic.name]
          h[dic.name].measure = Simstring::Jaccard
          h[dic.name].threshold = threshold
        end
        h
      end

      search_method = superfluous ? Dictionary.method(:search_term_order) : Dictionary.method(:search_term_top)

      r = labels.inject({}) do |h, label|
        h[label] = search_method.call(dictionaries, sim_string_dbs, threshold, label)
        h[label].map!{|entry| entry[:identifier]} unless verbose
        h
      end

      sim_string_dbs.each{|name, db| db.close if db}

      r
    end
  end

  # Override the original to_param so that it returns name, not ID, for constructing URLs.
  # Use Model#find_by_name() instead of Model.find() in controllers.
  def to_param
    name
  end

  def editable?(user)
    user && (user.admin? || user_id == user.id || associated_managers.include?(user))
  end

  def administrable?(user)
    user && (user.admin? || user_id == user.id)
  end

  def create_addition(label, id)
    increment!(:entries_num) if create_additional_entry(id, label)
    update_tmp_sim_string_db
  end

  def create_deletion(entry)
    entry.be_deletion!
    decrement!(:entries_num)
  end

  def undo_entry(entry)
    if entry.addition?
      entry.delete
      decrement!(:entries_num)
    elsif entry.deletion?
      entry.be_normal!
      increment!(:entries_num)
    end

    update_tmp_sim_string_db
  end

  def num_addition
    entries.where(mode:Entry::MODE_ADDITION).count
  end

  def num_deletion
    entries.where(mode:Entry::MODE_DELETION).count
  end

  def add_entries(pairs, normalizer = nil)
    transaction do
      new_entries = pairs.map {|label, identifier| new_entry_params(id, label, identifier, normalizer)}

      r = Entry.ar_import new_entries, validate: false
      raise "Import error" unless r.failed_instances.empty?

      increment!(:entries_num, new_entries.length)
    end
  end

  def new_entry_params(dictionary_id, label, id, normalizer)
    norm1 = normalize1(label, normalizer)
    norm2 = normalize2(label, normalizer)
    Entry.new(label: label, identifier: id, norm1: norm1, norm2: norm2, label_length: label.length, dictionary_id: dictionary_id)
  rescue => e
    raise ArgumentError, "The entry, [#{label}, #{id}], is rejected: #{e.message} #{e.backtrace.join("\n")}."
  end

  def empty_entries
    transaction do
      # Generate to one delete SQL statement for performance
      entries.delete_all
      update_attribute(:entries_num, 0)
    end
  end

  def sim_string_db_path
    Rails.root.join(sim_string_db_dir, "simstring.db").to_s
  end

  def tmp_sim_string_db_path
    Rails.root.join(sim_string_db_dir, "tmp_entries.db").to_s
  end

  def compile
    FileUtils.mkdir_p(sim_string_db_dir) unless Dir.exist?(sim_string_db_dir)
    db = Simstring::Writer.new sim_string_db_path, 3, false, true

    entries
      .where(mode: [Entry::MODE_NORMAL, Entry::MODE_ADDITION])
      .pluck(:norm2)
      .uniq
      .each{|norm2| db.insert norm2}

    # Generate to one delete SQL statement for performance
    Entry.delete(Entry.where(dictionary_id: self.id, mode:Entry::MODE_DELETION).pluck(:id))
    entries.where(mode:Entry::MODE_ADDITION).update_all(mode: Entry::MODE_NORMAL)

    db.close
  end

  def compilable?
    num_addition > 0 || num_deletion > 0
  end

  def narrow_entries_by_identifier(str, page = 0)
    Entry.where("identifier ILIKE ?", "%#{str}%").page(page)
  end

  def narrow_entries_by_label(str, dictionary = nil, page = 0)
    norm1 = normalize1(str)
    entries.where("norm1 LIKE ?", "%#{norm1}%").order(:label_length).page(page)
  end

  def narrow_entries_by_label_prefix(str, page = 0)
    norm1 = normalize1(str)
    entries.where("norm1 LIKE ?", "#{norm1}%").order(:label_length).page(page)
  end

  def narrow_entries_by_identifier(str, page = 0)
    entries.where("identifier ILIKE ?", "%#{str}%").page(page)
  end

  def self.narrow_entries_by_label(str, page = 0)
    norm1 = normalize1(str)
    Entry.where("norm1 LIKE ?", "#{norm1}%").order(:label_length).page(page)
  end

  def self.narrow_entries_by_label_prefix(str, page = 0)
    norm1 = normalize1(str)
    Entry.where("norm1 LIKE ?", "#{norm1}%").order(:label_length).page(page)
  end

  def self.search_term(dictionaries, ssdbs, term, norm1 = nil, norm2 = nil)
    return [] if term.empty?

    dictionaries.inject([]) do |sum, dic|
      sum + dic.search_term(ssdbs[dic.name], term, norm1, norm2)
    end
  end

  def self.search_term_order(dictionaries, ssdbs, threshold, term, norm1 = nil, norm2 = nil)
    entries = self.search_term(dictionaries, ssdbs, term, norm1, norm2)
    entries.delete_if{|e| e[:score] < threshold}
    entries.sort_by{|e| e[:score]}.reverse
  end

  def self.search_term_top(dictionaries, ssdbs, threshold, term, norm1 = nil, norm2 = nil)
    entries = self.search_term(dictionaries, ssdbs, term, norm1, norm2)
    return [] if entries.empty?
    max_score = entries.max{|a, b| a[:score] <=> b[:score]}[:score]
    return [] if max_score < threshold
    entries = entries.delete_if{|e| e[:score] < max_score}
  end

  def search_term(ssdb, term, norm1 = nil, norm2 = nil)
    return [] if term.empty?
    norm1 ||= normalize1(term)
    norm2 ||= normalize2(term)

    results  = []
    norm2s   = ssdb.retrieve(norm2) if ssdb
    results += norm2s.inject([]){|sum, norm2| sum + entries.where(norm2:norm2, mode:Entry::MODE_NORMAL)} if norm2s
    results += entries.where(mode:Entry::MODE_ADDITION)
    return [] if results.empty?

    results.map!{|e| {label: e.label, identifier:e.identifier, norm1: e.norm1, norm2: e.norm2}}.uniq!
    results.map!{|e| e.merge(score: Entry.str_jaccard_sim(term, norm1, norm2, e[:label], e[:norm1], e[:norm2]))}
  end

  private

  def create_additional_entry(id, label)
    e = entries.find_by_label_and_identifier(label, id)
    return unless e.nil?

    norm1 = normalize1(label)
    norm2 = normalize2(label)
    entries.create({label: label, identifier: id, norm1: norm1, norm2: norm2, label_length: label.length, mode: Entry::MODE_ADDITION})
    true
  end

  def sim_string_db_dir
    Dictionary::SIM_STRING_DB_DIR + self.name
  end

  def update_tmp_sim_string_db
    FileUtils.mkdir_p(sim_string_db_dir) unless Dir.exist?(sim_string_db_dir)
    db = Simstring::Writer.new tmp_sim_string_db_path, 3, false, true
    self.entries.where(mode: [Entry::MODE_NORMAL, Entry::MODE_ADDITION]).pluck(:norm2).uniq.each{|norm2| db.insert norm2}
    db.close
  end

  # Get typographic normalization of an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def normalize1(text, analyzer = nil)
    Entry.normalize(text, normalizer1, analyzer)
  end

  def self.normalize1(text, analyzer = nil)
    Entry.normalize(text, 'normalizer1', analyzer)
  end

  # Get typographic and morphosyntactic normalization of an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def normalize2(text, analyzer = nil)
    Entry.normalize(text, normalizer2, analyzer)
  end

  def self.normalize2(text, analyzer = nil)
    Entry.normalize(text, 'normalizer2', analyzer)
  end

  def normalizer1
    @normalizer1 ||= 'normalizer1' + language_suffix
  end

  def normalizer2
    @normalizer2 ||= 'normalizer2' + language_suffix
  end

  def language_suffix
    @language_suffix ||= if languages.empty?
      ''
    else
      case languages.first.abbreviation
      when 'KO'
        '_ko'
      when 'JA'
        '_ja'
      else
        ''
      end
    end
  end
end
