require 'fileutils'
require 'rubygems'
require 'zip'
require 'simstring'
using HashToResultHash

class Dictionary < ApplicationRecord
  include StringManipulator

  belongs_to :user
  has_many :associations
  has_many :associated_managers, through: :associations, source: :user
  has_many :entries, :dependent => :destroy
  has_many :patterns, :dependent => :destroy
  has_many :jobs, :dependent => :destroy
  has_many :tags, :dependent => :destroy

  validates :name, presence:true, uniqueness: true
  validates :user_id, presence: true
  validates :description, presence: true
  validates :license_url, url: {allow_blank: true}
  validates :name, length: {minimum: 3}
  validates_format_of :name,                              # because of to_param overriding.
                      :with => /\A[a-zA-Z_][a-zA-Z0-9_\- ()]*\z/,
                      :message => "should begin with an alphabet or underscore, and only contain alphanumeric letters, underscore, hyphen, space, or round brackets!"
  # validates :associated_annotation_project, length: { minimum: 5, maximum: 40 }
  # validates_format_of :associated_annotation_project, :with => /\A[a-z0-9\-_]+\z/i

  DOWNLOADABLES_DIR = 'db/downloadables/'

  SIM_STRING_DB_DIR = "db/simstring/"

  # The terms which will never be included in terms
  NO_TERM_WORDS = %w(are am be was were do did does had has have what which when where who how if whether an the this that these those is it its we our us they their them there then I he she my me his him her will shall may can cannot would should might could ought each every many much very more most than such several some both even and or but neither nor not never also much as well many e.g)

  # terms will never begin or end with these words, mostly prepositions
  NO_BEGIN_WORDS = %w(a am an and are as about above across after against along amid among around at been before behind below beneath beside besides between beyond by concerning considering despite do except excepting excluding for from had has have i in inside into if is it like my me of off on onto regarding since through to toward towards under underneath unlike until upon versus via with within without during what which when where who how whether)

  NO_END_WORDS = %w(a am an and are as about above across after against along amid among around at been before behind below beneath beside besides between beyond by concerning considering despite do except excepting excluding for from had has have i in inside into if is it like my me of off on onto regarding since through to toward towards under underneath unlike until upon versus via with within without during what which when where who how whether)

  def filename
    @filename ||= name.gsub(/\s+/, '_')
  end

  scope :mine, -> (user) {
    if user.nil?
      none
    else
      includes(:associations)
        .where('dictionaries.user_id = ? OR associations.user_id = ?', user.id, user.id)
        .references(:associations)
    end
  }

  scope :visible, -> (user) {
    if user.nil?
      where(public: true)
    elsif user.admin?
    else
      includes(:associations)
        .where('public = true OR dictionaries.user_id = ? OR associations.user_id = ?', user.id, user.id)
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

  scope :index_dictionaries, -> { where(public: true).order(created_at: :desc) }

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

      dictionaries = dic_names.split(/[,|]/).collect{|d| [d.strip, Dictionary.find_by(name: d.strip)]}
      unknown = dictionaries.select{|d| d[1].nil?}.collect{|d| d[0]}
      raise ArgumentError, "unknown dictionary: #{unknown.join(', ')}." unless unknown.empty?

      dictionaries.collect{|d| d[1]}
    end

    def find_ids_by_labels(labels, dictionaries = [], threshold = nil, superfluous = false, verbose = false, ngram = true, tags = [])
      sim_string_dbs = dictionaries.inject({}) do |h, dic|
        h[dic.name] = begin
          Simstring::Reader.new(dic.sim_string_db_path)
        rescue
          nil
        end
        if h[dic.name]
          h[dic.name].measure = Simstring::Jaccard
          h[dic.name].threshold = threshold || dic.threshold
        end
        h
      end

      search_method = superfluous ? Dictionary.method(:search_term_order) : Dictionary.method(:search_term_top)

      r = labels.inject({}) do |h, label|
        h[label] = search_method.call(dictionaries, sim_string_dbs, threshold, ngram, label, tags)
        h[label].map!{|entry| entry[:identifier]} unless verbose
        h
      end

      sim_string_dbs.each{|name, db| db.close if db}

      r
    end

    def find_labels_by_ids(ids, dictionaries = [])
      entries = if dictionaries.present?
        Entry.where(identifier: ids, dictionary_id: dictionaries)
      else
        Entry.where(identifier: ids)
      end

      entries.each_with_object({}) do |entry, h|
        h[entry.identifier] = [] unless h.has_key? entry.identifier
        h[entry.identifier] << {label: entry.label, dictionary: entry.dictionary.name}
      end
    end
  end

  # Override the original to_param so that it returns name, not ID, for constructing URLs.
  # Use Model#find_by_name() instead of Model.find() in controllers.
  def to_param
    name
  end

  def empty?
    entries_num == 0
  end

  def editable?(user)
    user && (user.admin? || user_id == user.id || associated_managers.include?(user))
  end

  def administrable?(user)
    user && (user.admin? || user_id == user.id)
  end

  def stable?
    (jobs.count == 0) || (jobs.count == 1 && jobs.first.finished?)
  end

  def uploadable?
    entries.empty?
  end

  def locked?
    jobs.size > 0 && jobs.first.running?
  end

  def use_tags?
    !tags.empty?
  end

  def undo_entry(entry)
    if entry.is_white?
      entry.destroy
    elsif entry.is_black?
      transaction do
        entry.be_gray!
        update_entries_num
      end
    end
  end

  def confirm_entries(entry_ids)
    transaction do
      entries = Entry.where(id: entry_ids)
      entries.each{ |entry| entry.be_white! }
      update_entries_num
    end
  end

  def update_entries_num
    non_black_num = entries.where.not(mode: EntryMode::BLACK).count
    update(entries_num: non_black_num)
  end

  def num_gray = entries.gray.count

  def num_white = entries.white.count

  def num_black = entries.black.count

  def num_auto_expanded = entries.auto_expanded.count

  # turn a gray entry to white
  def turn_to_white(entry)
    raise "Only a gray entry can be turned to white" unless entry.mode == EntryMode::GRAY
    entry.be_white!
  end

  # turn a gray entry to black
  def turn_to_black(entry)
    raise "Only a gray entry can be turned to black" unless entry.mode == EntryMode::GRAY
    transaction do
      entry.be_black!
      update_entries_num
    end
  end

  # cancel a black entry to gray
  def cancel_black(entry)
    raise "Ony a black entry can be canceled to gray" unless entry.mode == EntryMode::BLACK
    transaction do
      entry.be_gray!
      update_entries_num
    end
  end

  def add_patterns(patterns)
    transaction do
      columns = [:expression, :identifier, :dictionary_id]
      r = Pattern.bulk_import columns, patterns.map{|p| p << id}, validate: false
      raise "Import error" unless r.failed_instances.empty?

      increment!(:patterns_num, patterns.length)
    end
  end

  def add_entries(raw_entries, norm1list, norm2list)
    # black_count = raw_entries.count{|e| e[2] == EntryMode::BLACK}

    transaction do
      # import tags
      tag_set = raw_entries.map{|(_, _, tags)| tags}.flatten.uniq
      new_tags = tag_set - tags.where(value: tag_set).pluck(:value)

      if new_tags.present?
        columns = [:value, :dictionary_id]
        values = new_tags.map{|tag| [tag, self.id]}
        r = Tag.bulk_import columns, values, validate: false
        raise "Error during import of tags" unless r.failed_instances.empty?
      end

      # import entries
      entries = raw_entries.map.with_index do |(label, identifier, _), i|
        [label, identifier, norm1list[i], norm2list[i], label.length, EntryMode::GRAY, false, self.id]
      end

      columns = [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id]
      values = entries
      r = Entry.bulk_import columns, values, validate: false
      raise "Error during import of entries" unless r.failed_instances.empty?

      # import entry_tags association
      tag_map = tags.where(value: tag_set).pluck(:value, :id).to_h
      entry_tags = raw_entries.map.with_index do |(_, _, tags), i|
        tags.map{|tag| [r.ids[i], tag_map[tag]]}
      end

      columns = [:entry_id, :tag_id]
      values = entry_tags.flatten(1)
      r = EntryTag.bulk_import columns, values, validate: false
      raise "Error during import of entry_tags" unless r.failed_instances.empty?

      update_entries_num
    end
  end

  def new_entry(label, identifier)
    analyzer = Analyzer.new
    norm1 = normalize1(label, analyzer)
    norm2 = normalize2(label, analyzer)
    entries.build(label: label,
                  identifier: identifier,
                  norm1: norm1,
                  norm2: norm2,
                  label_length: label.length,
                  mode: EntryMode::WHITE,
                  dirty: true)
  rescue => e
    raise ArgumentError, "The entry, [#{label}, #{identifier}], is rejected: #{e.message} #{e.backtrace.join("\n")}."
  end

  def create_entry!(label, identifier, tag_ids = [])
    entry = new_entry(label, identifier)
    entry.tag_ids = tag_ids
    entry.save!

    entry
  end

  def empty_entries(mode = nil)
    transaction do
      case mode
      when nil
        EntryTag.where(entry_id: entries.pluck(:id)).delete_all
        entries.delete_all
        update_entries_num
        clean_sim_string_db
      when EntryMode::GRAY
        entries.gray.destroy_all
      when EntryMode::WHITE
        entries.white.destroy_all
      when EntryMode::BLACK
        entries.black.each{|e| cancel_black(e)}
      when EntryMode::AUTO_EXPANDED
        entries.auto_expanded.destroy_all
      else
        raise ArgumentError, "Unexpected mode: #{mode}"
      end
    end
  end

  def clear_tags
    tags.destroy_all
  end

  def new_pattern(expression, identifier)
    Pattern.new(expression:expression, identifier:identifier, dictionary_id: self.id)
    rescue => e
      raise ArgumentError, "The pattern, [#{expression}, #{identifier}], is rejected: #{e.message} #{e.backtrace.join("\n")}."
  end

  def empty_patterns
    transaction do
      patterns.delete_all
      update_attribute(:patterns_num, 0)
    end
  end

  def sim_string_db_path
    Rails.root.join(sim_string_db_dir, "simstring.db").to_s
  end

  def tmp_sim_string_db_path
    Rails.root.join(sim_string_db_dir, "tmp_entries.db").to_s
  end

  def sim_string_db_exist?
    File.exist?(sim_string_db_path)
  end

  def additional_entries_exists?
    @additional_entries_exists
  end

  def additional_entries_existency_update
    @additional_entries_exists = entries.additional_entries.exists?
  end

  def tags_exists?
    @tag_exists
  end

  def tags_existency_update
    @tag_exists = use_tags?
  end

  def compilable?
    entries.exists? && (entries.where(dirty:true).exists? || !sim_string_db_exist?)
  end

  def compile!
    # Update sim string db to remove black entries and to add (dirty) white entries.
    # which is sufficient to speed up the search
    update_sim_string_db

    # commented: do NOT delete black entries
    # Entry.delete(Entry.where(dictionary_id: self.id, mode:EntryMode::BLACK).pluck(:id))

    # commented: do NOT change white entries to gray ones
    # entries.where(mode:EntryMode::WHITE).update_all(mode: EntryMode::GRAY)

    update_stop_words
  end

  def update_stop_words
    mlabels = entries.pluck(:label).map{|l| l.downcase.split}
    count_no_term_words = mlabels.map{|ml| ml & NO_TERM_WORDS}.select{|i| i.present?}.reduce([], :+).uniq
    count_no_begin_words = mlabels.map{|ml| ml[0, 1] & NO_BEGIN_WORDS}.select{|i| i.present?}.reduce([], :+).uniq
    count_no_end_words = mlabels.map{|ml| ml[-1, 1] & NO_END_WORDS}.select{|i| i.present?}.reduce([], :+).uniq
    self.no_term_words = NO_TERM_WORDS - count_no_term_words
    self.no_begin_words = NO_BEGIN_WORDS - count_no_begin_words
    self.no_end_words = NO_END_WORDS - count_no_end_words
    self.save!
  end

  def simstring_method
    @simstring_method ||= case language
    when 'kor'
      Simstring::Cosine
    when 'jpn'
      Simstring::Cosine
    else
      Simstring::Jaccard
    end
  end

  def self.search_term_order(dictionaries, ssdbs, threshold, ngram, term, tags, norm1 = nil, norm2 = nil)
    return [] if term.empty?

    entries = dictionaries.inject([]) do |sum, dic|
      sum + dic.search_term(ssdbs[dic.name], term, norm1, norm2, tags, threshold, ngram)
    end

    entries.sort_by{|e| e[:score]}.reverse
  end

  def self.search_term_top(dictionaries, ssdbs, threshold, ngram, term, tags, norm1 = nil, norm2 = nil)
    return [] if term.empty?

    entries = dictionaries.inject([]) do |sum, dic|
      sum + dic.search_term(ssdbs[dic.name], term, norm1, norm2, tags, threshold, ngram)
    end

    return [] if entries.empty?

    max_score = entries.max{|a, b| a[:score] <=> b[:score]}[:score]
    entries.delete_if{|e| e[:score] < max_score}
  end

  def search_term(ssdb, term, norm1, norm2, tags, threshold, ngram)
    return [] if term.empty? || entries_num == 0

    threshold ||= self.threshold

    # It needs for a proper sensitivity over additional entities
    # results = additional_entries tags

    if threshold < 1
      results = []

      norm1 ||= normalize1(term)
      norm2 ||= normalize2(term)
      norm2s = ssdb.retrieve(norm2) if ngram && ssdb.present?
      norm2s = [norm2] unless norm2s.present?

      norm2s.each do |n2|
        results += additional_entries_for_norm2(n2, tags) if additional_entries_exists?
        results += self.entries
                       .left_outer_joins(:tags)
                       .without_black
                       .where(norm2: n2)
                       .then{ tags.present? ? _1.where(tags: { value: tags }) : _1 }
      end

      if tags_exists?
        results.map!(&:to_result_hash_with_tags)
      else
        results.map!(&:to_result_hash)
      end

      results.uniq!
      results.each{|e| e.merge!(score: str_sim.call(term, e[:label], norm1, e[:norm1], norm2, e[:norm2]), dictionary: name)}
      results.delete_if{|e| e[:score] < threshold}
    else
      results = additional_entries_for_label(term, tags)
      results += self.entries
                     .left_outer_joins(:tags)
                     .without_black
                     .where(label: term)
                     .then{ tags.present? ? _1.where(tags: { value: tags }) : _1 }
                     .map(&:to_result_hash)
      results.each{|e| e.merge!(score: 1, dictionary: name)}
    end
  end

  def sim_string_db_dir
    Dictionary::SIM_STRING_DB_DIR + self.name
  end

  def update_db_location(db_loc_old)
    db_loc_new = self.sim_string_db_dir
    if Dir.exist?(db_loc_old)
      FileUtils.mv db_loc_old, db_loc_new unless db_loc_new == db_loc_old
    else
      FileUtils.mkdir_p(db_loc_new)
    end
  end

  def downloadable_zip_path
    @downloadable_path ||= DOWNLOADABLES_DIR + filename + '.zip'
  end

  def large?
    entries_num > 10000
  end

  def creating_downloadable?
    jobs.any?{|job| job.name == 'Create downloadable'}
  end

  def downloadable_updatable?
    if File.exist?(downloadable_zip_path)
      updated_at > File.mtime(downloadable_zip_path)
    else
      true
    end
  end

  def create_downloadable!
    FileUtils.mkdir_p(DOWNLOADABLES_DIR) unless Dir.exist?(DOWNLOADABLES_DIR)

    buffer = Zip::OutputStream.write_buffer do |out|
      out.put_next_entry(self.name + '.csv')
      out.write entries.as_tsv
    end

    File.open(downloadable_zip_path, 'wb') do |f|
      f.write(buffer.string)
    end
  end

  def save_tags(tag_list)
    tag_list.each do |tag|
      self.tags.create!(value: tag)
    end
  end

  def update_tags(tag_list)
    current_tags = self.tags.to_a

    tags_to_add = tag_list.reject { |tag_value| current_tags.any? { |t| t.value == tag_value } }
    tags_to_remove = current_tags.reject { |tag| tag_list.include?(tag.value) }

    tags_to_add.each do |tag|
      self.tags.create!(value: tag)
    end

    tags_in_use = []
    tags_to_remove.each do |tag|
      if tag.used_in_entries?
        tags_in_use << tag.value
      else
        tag.destroy
      end
    end

    if tags_in_use.any?
      errors.add(:base, "The following tags #{tags_in_use.to_sentence} #{tags_in_use.length > 1 ? 'are' : 'is'} used. Please edit the entry before deleting.")
      return false
    end

    true
  end

  def expand_synonym
    start_time = Time.current
    batch_size = 1000
    processed_identifiers = Set.new

    identifiers_count =  entries.active.select(:identifier).distinct.count
    batch_count = identifiers_count / batch_size

    0.upto(batch_count) do |i|
      current_batch = entries.active
                              .select(:identifier)
                              .distinct
                              .order(:identifier)
                              .simple_paginate(i + 1, batch_size)
                              .pluck(:identifier)
      break if current_batch.empty?

      new_identifiers = current_batch.reject { |identifier| processed_identifiers.include?(identifier) }
      new_identifiers.each do |identifier|
        synonyms = entries.active
                          .where(identifier: identifier)
                          .where("created_at < ?", start_time)
                          .pluck(:label)
        expanded_synonyms = synonym_expansion(synonyms)
        append_expanded_synonym_entries(identifier, expanded_synonyms)
        processed_identifiers.add(identifier)
      end
    end
  end

  def synonym_expansion(synonyms)
    synonyms.map.with_index do |label, i|
      expanded_label = "#{label}--dummy-synonym-#{i + 1}"
      score = rand
      { label: expanded_label, score: }
    end
  end

  def normalizer1
    @normalizer1 ||= 'normalizer1' + language_suffix
  end

  def normalizer2
    @normalizer2 ||= 'normalizer2' + language_suffix
  end

  private

  def ngram_order
    case language
    when 'kor'
      2
    when 'jpn'
      1
    else
      3
    end
  end

  def clean_sim_string_db
    FileUtils.rm_rf Dir.glob("#{sim_string_db_dir}/*")
  end

  def update_sim_string_db
    FileUtils.mkdir_p(sim_string_db_dir) unless Dir.exist?(sim_string_db_dir)
    clean_sim_string_db

    db = Simstring::Writer.new sim_string_db_path, ngram_order, false, true

    entries
      .active
      .pluck(:norm2)
      .uniq
      .compact # to avoid error
      .each{|norm2| db.insert norm2}

    db.close

    entries.white.update_all(dirty: false)
  end

  def update_tmp_sim_string_db
    FileUtils.mkdir_p(sim_string_db_dir) unless Dir.exist?(sim_string_db_dir)
    db = Simstring::Writer.new tmp_sim_string_db_path, 3, false, true
    self.entries.where(mode: [EntryMode::GRAY, EntryMode::WHITE]).pluck(:norm2).uniq.each{|norm2| db.insert norm2}
    db.close
  end

  # Get typographic normalization of an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def normalize1(text, analyzer = Analyzer.new)
    analyzer.normalize(text, normalizer1)
  end

  def self.normalize1(text, analyzer = Analyzer.new)
    analyzer.normalize(text, 'normalizer1')
  end

  # Get typographic and morphosyntactic normalization of an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def normalize2(text, analyzer = Analyzer.new)
    analyzer.normalize(text, normalizer2)
  end

  def language_suffix
    @language_suffix ||= if language.present?
      case language
      when 'kor'
        '_ko'
      when 'jpn'
        '_ja'
      else
        ''
      end
    else
      ''
    end
  end

  def str_sim
    @str_sim ||= case language
    when 'kor'
      Entry.method(:str_sim_jaccard_2gram)
    when 'jpn'
      Entry.method(:str_sim_jp)
    else
      Entry.method(:str_sim_jaccard_3gram)
    end
  end

  def append_expanded_synonym_entries(identifier, expanded_synonyms)
    transaction do
      expanded_synonyms.each do |expanded_synonym|
        entries.create!(
          label: expanded_synonym[:label],
          identifier: identifier,
          score: expanded_synonym[:score],
          mode: EntryMode::AUTO_EXPANDED
        )
      end
    end
  end

  def maintainer
    self.user.username
  end

  def dic_created_at
    self.created_at.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  def additional_entries(tags)
    self.entries
        .left_outer_joins(:tags)
        .additional_entries
        .then{ tags.present? ? _1.where(tags: { value: tags }) : _1 }
        .map(&:to_result_hash)
  end

  def additional_entries_for_norm2(norm2, tags)
    self.entries
        .left_outer_joins(:tags)
        .additional_entries
        .where(norm2: norm2)
        .then{ tags.present? ? _1.where(tags: { value: tags }) : _1 }
        .map(&:to_result_hash)
  end

  def additional_entries_for_label(label, tags)
    self.entries
        .left_outer_joins(:tags)
        .additional_entries
        .where(label: label)
        .then{ tags.present? ? _1.where(tags: { value: tags }) : _1 }
        .map(&:to_result_hash)
  end
end
