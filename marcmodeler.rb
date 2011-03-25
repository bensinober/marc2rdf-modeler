#!/usr/bin/env ruby
require 'rubygems'
#require 'marc'
require 'jcode' if RUBY_VERSION < '1.9'
require 'enhanced_marc'
require './rdf_resource'
require './lcsh_labels'
require 'isbn/tools'

# quit unless our script gets two command line arguments 
unless ARGV.length > 1
  puts "Missing input file!"
  puts "Usage: ruby marcmodeler.rb InputFile.mrc [OutputFile.rdf]\n"
  exit
end

# our input file should be the first command line arg
input_file = ARGV[0]

# our output file should be the second command line arg
output_file = ARGV[1]

# forgiving reader (marc is full of empty holes...)
reader = MARC::ForgivingReader.new(input_file)

# unforgiving reader, expects strict marc ...
#reader = MARC::Reader.new(input_file)

i = 0

class String
=begin
 added function definitions to default string:
 slug : regex, removes everything but word, character or '-'
 strip_trailing_punct 
 strip_leading_and_trailing_punct
 lpad : ?
=end
  def slug
    slug = self.gsub(/[^\w\s\-]/,"")
    slug.gsub!(/\s/,"_")
    slug.downcase
  end  
  def strip_trailing_punct
    self.sub(/[\.:,;\/\s]\s*$/,'').strip
  end
  def strip_leading_and_trailing_punct
    str = self.sub(/[\.:,;\/\s\)\]]\s*$/,'').strip
    return str.strip.sub(/^\s*[\.:,;\/\s\(\[]/,'')
  end  
  def lpad(count=1)
    "#{" " * count}#{self}"
  end
end

class MARC::Record
=begin
   the actual RDF extension class to MARC::Record
   new functions:
     subdivided?(subject)
     subject_to_string(subject)
     top_concept(subject)
     to_rdf_resources
     relate_identity(datafield, resource, identity)
     to_rdf_resources
     
=end
  @@base_uri = 'http://koha.deichman.no/rdfstore'
  @@missing_id_prefix = 'pode'
  @@missing_id_counter = 0
  @@relators = YAML::load_file('relation.yml')
    
  def subdivided?(subject)
    subject.subfields.each do | subfield |
      if ["k","v","x","y","z"].index(subfield.code)
        return true
      end
    end
    return false
  end
  
  # function: converts subject from subject's subfield v,x,y or z to string literal
  def subject_to_string(subject)
    literal = ''
    subject.subfields.each do | subfield |
      if !literal.empty?
        if ["v","x","y","z"].index(subfield.code)
          literal << '--'
        else
          literal << ' ' if subfield.value =~ /^[\w\d]/
        end
      end
      literal << subfield.value
    end
    literal.strip_trailing_punct  
  end
  
  # function: parses marc fields for subject and appends subfield to marc
  def top_concept(subject)
    field = MARC::DataField.new(subject.tag, subject.indicator1, subject.indicator2)
    subject.subfields.each do | subfield |
      unless ["k","v","x","y","z"].index(subfield.code)
        sub = MARC::Subfield.new(subfield.code, subfield.value)
        field.append(sub)
      end
    end
    return field
  end
  
  # main function for converting to RDF
  def to_rdf_resources
    resources = []
    # appends controlfield 001 if missing
    unless self['001']
      controlnum = MARC::ControlField.new('001')
      controlnum.value = "#{@@missing_id_prefix}#{@@missing_id_counter}"
      @@missing_id_counter += 1
      self << controlnum
    end
    # gets 001 value, gives resource an uri and relates as manifestation
    id = self['001'].value.strip
    resources << manifestation = RDFResource.new("#{@@base_uri}/m/#{id}")    
    manifestation.relate("[rdf:type]", "[frbr:Manifestation]")
    
    
=begin
    Get dct:title from tags 245, subfield $a
    find_all returns all elements that matches block expression into object array 
    enum.find_all { |object array | block expression }
=end

    titles = self.find_all {|field| field.tag =~ /^245/}
    
    titles.each do | title |
        if title['a']
          manifestation.assert("[dct:title]", title['a'])
        end
        if title['b']
          manifestation.assert("[rda:otherTitleInformation]", title['b'])
        end
        if title['c']
          manifestation.assert("[rda:statementOfResponsibility]", title['c'])
        end
        if title['n']
          manifestation.assert("[bibo:number]", title['n'])
        end
    end 

=begin   
    if self['245']
      if self['245']['a']
        title = self['245']['a'].strip_trailing_punct
        manifestation.assert("[rda:titleProper]", self['245']['a'].strip_trailing_punct)
      end
      if self['245']['b']
        title << " "+self['245']['b'].strip_trailing_punct
        manifestation.assert("[rda:otherTitleInformation]", self['245']['b'].strip_trailing_punct)
      end
      if self['245']['c']
        manifestation.assert("[rda:statementOfResponsibility]", self['245']['c'].strip_trailing_punct)
      end
      if self['245']['n']
        manifestation.assert("[bibo:number]", self['245']['n'])
      end
    end
    manifestation.assert("[dct:title]", title)
    if self['210']
      manifestation.assert("[bibo:shortTitle]", self['210']['a'].strip_trailing_punct)
    end
=end

    if self['020'] && self['020']['a']
      isbn = ISBN_Tools.cleanup(self['020']['a'].strip_trailing_punct)
      if ISBN_Tools.is_valid?(isbn)
        #manifestation.assert("[bibo:isbn]", isbn)
        if isbn.length == 10
          manifestation.assert("[bibo:isbn10]",isbn)
          manifestation.assert("[bibo:isbn13]", ISBN_Tools.isbn10_to_isbn13(isbn))
        else
          manifestation.assert("[bibo:isbn13]",isbn)
          manifestation.assert("[bibo:isbn10]", ISBN_Tools.isbn13_to_isbn10(isbn))          
        end
      end
    end
    
    if self['022'] && self['022']['a']
      manifestation.assert("[bibo:issn]", self['022']['a'].strip_trailing_punct)
    end    
    if self['250'] && self['250']['a']
      manifestation.assert("[bibo:edition]", self['250']['a'])
    end
    if self['246'] && self['246']['a']
      manifestation.assert("[rda:parallelTitleProper]", self['246']['a'].strip_trailing_punct)
    end
    if self['767'] && self['767']['t']
      manifestation.assert("[rda:parallelTitleProper]", self['767']['t'].strip_trailing_punct)
    end    

=begin
    Get dct:description from tags 5xx, subfield $a
    Unless 571, then bibo:identiifer
    find_all returns all elements that matches block expression into object array 
    enum.find_all { |object array | block expression }
=end

    descriptions = self.find_all {|field| field.tag =~ /^5../}
    
    descriptions.each do | description |
      unless ["571"].index(description.tag)
        if description['a']
          manifestation.assert("[dct:description]", description['a'])
        end
      else
        if description['a']
          manifestation.assert("[bibo:identifier]", description['a'])
        end
      end
    end 
    
    subjects = self.find_all {|field| field.tag =~ /^6../}
    
    subjects.each do | subject |
      authority = false
      authorities = []
      literal = subject_to_string(subject)
      manifestation.assert("[dc:subject]", literal)
      if !["653","690","691","696","697", "698", "699"].index(subject.tag) && subject.indicator2 =~ /^(0|1)$/        
        Label.all(:label=>literal).each do | auth |    
          next if (subject.indicator2 == "0" && auth.uri =~ /http:\/\/lcsubjects\.org\/subjects\/sj/) || 
            (subject.indicator2 == "1" && auth.uri =~ /http:\/\/lcsubjects\.org\/subjects\/sh/)
          manifestation.relate("[dct:subject]", auth.uri)
          authorities << auth.uri
          authority = true
        end
      end
      if ["600","610","611","630"].index(subject.tag) || !authority
        
        if subject.tag =~ /^(600|610|696|697)$/
          unless subdivided?(subject)
            concept = RDFResource.new("#{@@base_uri}/#{Identity.path(subject)}/#{literal.slug}#concept")
            identity = RDFResource.new("#{@@base_uri}/#{Identity.path(subject)}/#{literal.slug}")
          else
            concept = RDFResource.new("#{@@base_uri}/subjects/#{literal.slug}#concept")
            identity_subject = top_concept(subject)
            identity = RDFResource.new("#{@@base_uri}/#{Identity.path(subject)}/#{subject_to_string(identity_subject).slug}")
          end
          if subject.tag =~ /^(600|696)$/
            identity.relate("[rdf:type]","[foaf:Person]")
            if subject['u']
              identity.assert("[ov:affiliation]", subject['u'].strip_trailing_punct)
            end
            concept.relate("[skos:inScheme]", "#{@@base_uri}/subjects#personalNames")
          else
            identity.relate("[rdf:type]","[foaf:Organization]")
            identity.assert("[dct:description]", subject['u'])
            concept.relate("[skos:inScheme]", "#{@@base_uri}/subjects#corporateNames")            
          end
          concept.relate("[rdfs:seeAlso]", identity.uri)
          identity.relate("[rdfs:seeAlso]", concept.uri)
          name = subject['a']
          if subject['b']
            name << " #{subject['b']}"
          end
          identity.assert("[foaf:name]",name)
          if subject['d']
            identity.assert("[dct:date]", subject['d'])
          end      
          resources << identity      
        elsif subject.tag =~ /^(611|698)$/
          if !subdivided?(subject)
            concept = RDFResource.new("#{@@base_uri}/events/#{literal.slug}#concept")
            event = RDFResource.new("#{@@base_uri}/events/#{literal.slug}")
          else
            concept = RDFResource.new("#{@@base_uri}/subjects/#{literal.slug}#concept")
            event_subject = top_concept(subject)
            event = RDFResource.new("#{@@base_uri}/events/#{subject_to_string(event_subject).slug}")
          end   
          concept.relate("[skos:inScheme]", "#{@@base_uri}/s#meetings")          
          event.relate("[rdf:type]","[event:Event]")
          concept.relate("[rdfs:seeAlso]", event.uri)
          event.relate("[rdfs:seeAlso]", concept.uri)          
          event.assert("[dct:title]", subject['a'])
          if subject['d']
            event.assert("[dct:date]", subject['d'])
          end
          if subject['c']
            event.assert("[dct:description]", subject['c'])
          end
          resources << event          
        elsif subject.tag =~ /^(630|699)$/
          unless subdivided?(subject)
            concept = RDFResource.new("#{@@base_uri}/w/#{literal.slug}#concept")
            work = RDFResource.new("#{@@base_uri}/w/#{literal.slug}")
          else
            concept = RDFResource.new("#{@@base_uri}/subjects/#{literal.slug}#concept")
            work_subject = top_concept(subject)
            work = RDFResource.new("#{@@base_uri}/w/#{subject_to_string(work_subject).slug}")
          end
          concept.relate("[skos:inScheme]", "#{@@base_uri}/s#uniformTitles")          
          work.relate("[rdf:type]","[frbr:Work]")
          concept.relate("[rdfs:seeAlso]", work.uri)
          work.relate("[rdfs:seeAlso]", concept.uri)          
          work.assert("[dct:title]", subject['a'])
          if subject['d']
            work.assert("[dct:date]", subject['d'])
          end
          if subject['f']
            work.assert("[dct:date]", subject['f'])
          end     
          resources << work     
        else
          concept = RDFResource.new("#{@@base_uri}/s/#{literal.slug}#concept")  
          if subject.tag =~ /^(650|690)$/
            concept.relate("[skos:inScheme]","#{@@base_uri}/s#topicalTerms")
          elsif subject.tag =~ /^(651|691)$/
            concept.relate("[skos:inScheme]","#{@@base_uri}/s#geographicNames")
          elsif subject.tag = "655"
            concept.relate("[skos:inScheme]","#{@@base_uri}/s#genreFormTerms")
          elsif subject.tag = "648"
            concept.relate("[skos:inScheme]","#{@@base_uri}/s#chronologicalTerms")
          elsif subject.tag = "656"
            concept.relate("[skos:inScheme]","#{@@base_uri}/s#occupations")
          end
        end
        concept.assert("[skos:prefLabel]", literal)
        
        authorities.each do | auth |
          concept.relate("[skos:exactMatch]", auth)
        end
        
        subject.subfields.each do | subfield |
          scheme = case subfield.code
          when "v" then "#{@@base_uri}/s#formSubdivision"
          when "x" then "#{@@base_uri}/s#generalSubdivision"
          when "y" then "#{@@base_uri}/s#chronologicalSubdivision"
          when "z" then "#{@@base_uri}/s#geographicSubdivision"
          else nil
          end
          if scheme
            concept.relate("[skos:inScheme]",scheme)
          end
        end
        resources << concept
        manifestation.relate("[dct:subject]", concept.uri)
      end
      authority = false
    end
    if self['010'] && self['010']['a']
      manifestation.assert("[bibo:lccn]", self['010']['a'].strip)
    end
    oclcnums = self.find_all {|field| field.tag == "035" && (field['a'] =~ /^\(OCoLC\)/ || field['b'] == "OCoLC")}
    oclcnums.each do | oclcnum |
      manifestation.assert("[bibo:oclcnum]",oclcnum['a'].sub(/^\(OCoLC\)/,''))
    end
    pages = self.find_all {|field| field.tag == "300" && (field['a'] =~ /\sp\./)}
    pages.each do | page |
      manifestation.assert("[bibo:pages]",page['a'].strip_trailing_punct)
    end
#    if self.form      
#      manifestation.assert("[dc:format]", self.form(true))
#    end

    identities = self.find_all{|field| field.tag =~ /100|110|400|410|700|710|720|790|791|796|797|800|810|896|897/}
    identities.each do | identity_field |
      identity = Identity.new_from_field(identity_field, "#{@@base_uri}/")
      resources << identity.resource
      relate_identity(identity_field, manifestation, identity)
    end 

#    meetings = self.find_all{|field| field.tag =~ /111|411|711|792|798|811|898/}
#    meetings.each do | meeting |
#      event = Event.new_from_field(meeting, "#{@@base_uri}/events/")
#      resources << event.resource
#      relate_event(meeting, manifestation, event)
#    end  

    if self['506'] && self['506']['a']
      manifestation.assert('[dct:accessRights]',self['506']['a'])
    end
#    if aud = self.audience_level(true)
#      audience = RDFResource.new("#{@@base_uri}/audiences/#{aud.slug}")
#      audience.relate("[rdf:type]","[dct:AgentClass]")
#      audience.assert("[dct:title]", aud)
#      manifestation.relate("[dct:audience]",audience.uri)
#      resources << audience
#    end
    
    # publication info
    if self['260']
      # publicationPlace
      if self['260']['a'] 
        manifestation.assert('[dct:publicationPlace]',self['260']['a'])
      end
      # publisher
      if self['260']['b'] 
        manifestation.relate("[rdf:type]", "[foaf:Organization]")
        manifestation.assert('[dct:publisher]',self['260']['b'])
      end
      # date
      subfield_c = self['260'].find_all {|subfield| subfield.code == 'c'}
      subfield_c.each do | c |
        if c.value =~ /\bc[0-9]/
          manifestation.assert("[dct:dateCopyrighted]", c.value.sub(/\bc/,''))
        else
          manifestation.assert("[dct:date]",c.value.strip_leading_and_trailing_punct)
        end
      end
    end
    resources
  end
  
  # parse yaml and identity fields and create relationships
  def relate_identity(datafield, resource, identity)
    if ["100","110"].index(datafield.tag)
      resource.relate("[dct:creator]", identity.resource.uri)
      resource.assert("[dc:creator]",identity.name)
    end
    relationships = []
    datafield.subfields.each do | subfield |
      next unless subfield.code == 'e' || subfield.code == '4'
      next unless @@relators[subfield.value.strip_trailing_punct]
      if pointer = @@relators[subfield.value.strip_trailing_punct]["use"]
        if @@relators[subfield.value.strip_trailing_punct]["use"].is_a?(Array)
          @@relators[subfield.value.strip_trailing_punct]["use"].each {|u| relationships << @@relators[u] }
        else
          relationships << @@relators[pointer]  
        end
      else
        relationships << @@relators[subfield.value.strip_trailing_punct]
      end      
    end
    
    unless relationships.empty?
      relationships.uniq.each do | rel |
        if rel["relationship"]
          if rel["relationship"].is_a?(Array)
            rel["relationship"].each do | r |
              resource.relate(r, identity.resource.uri)
            end
          else
            resource.relate(rel['relationship'], identity.resource.uri)
          end
        end
        if rel["literal"]
          resource.assert(rel['literal'], identity.name)
        end
      end
    else
      unless ["100","110"].index(datafield.tag)
        resource.relate("[dct:contributor]", identity.resource.uri)
        resource.assert("[dct:contributor]", identity.name)        # fixed typo: dc:contributor
      end
    end
  end
end

class MARC::BookRecord
  def to_rdf_resources
    resources = super
    book = resources[0]
    if self.is_conference?
     book.relate("[rdf:type]","[bibo:Proceedings]")
    elsif self.is_manuscript?
      book.relate("[rdf:type]","[bibo:Manuscript]")
#    elsif self.nature_of_contents.index("m")
#      book.relate("[rdf:type]","[bibo:Thesis]")
#    elsif self.nature_of_contents.index("u")
#      book.relate("[rdf:type]","[bibo:Standard]")
#    elsif self.nature_of_contents.index("j")
#      book.relate("[rdf:type]","[bibo:Patent]")    
#    elsif self.nature_of_contents.index("t")
#      book.relate("[rdf:type]","[bibo:Report]")
#    elsif self.nature_of_contents.index("l")
#      book.relate("[rdf:type]","[bibo:Legislation]")
#    elsif  self.nature_of_contents.index("v")
#      book.relate("[rdf:type]","[bibo:LegalCaseDocument]")
#    elsif !(self.nature_of_contents & ["c", "d", "e", "r"]).empty?
#      book.relate("[rdf:type]","[bibo:ReferenceSource]")
    else
      book.relate("[rdf:type]", "[bibo:Book]")
    end
 #   if self.nature_of_contents
 #     self.nature_of_contents(true).each do | genre |        
 #       book.assert("[dct:type]", genre)
 #     end
 #   end
    #puts book.to_rdfxml
    return resources
  end
end

class MARC::VisualRecord
  def to_rdf_resources
    resources = super
    vis = resources[0]
    type = self.material_type(true)
    if type == "Videorecording" or (self['245'] && self['245']['h'] && self['245']['h'] =~ /videorecording/)
      vis.relate("[rdf:type]","[bibo:Film]")
    elsif type
      vis.assert("[dct:type]", type)
    end
    return resources
  end
end

class Identity
=begin
  Identity class for creating inferred identity resources 
  functions:
    new_from_field(field, base_uri)
    path(datafield)						
    relations(field)    				# empty
=end
  attr_accessor :name, :resource
  def self.new_from_field(field, base_uri)
    identity = self.new
    name = ''

    personal = ["100","400","700","790","796", "800","896"]
    corporate = ["110","410","710","791","797", "810", "897"]

    if personal.index(field.tag)
      name << field['a']
      ['b','c','d','q'].each do | code |
        name << field[code].lpad if field[code]
      end
    elsif corporate.index(field.tag)
      name << field['a'].strip_trailing_punct
      ['b','c','d'].each do | code |
        name << field[code].lpad if field[code]
      end
    elsif field.tag == "720"
      name = field['a'].strip_trailing_punct
    end   
    identity.name = name.strip_trailing_punct   
    resource = RDFResource.new("#{base_uri}#{self.path(field)}/#{name.slug}")
    if personal.index(field.tag)
      resource.relate("[rdf:type]", "[foaf:Person]")
      if field.indicator1 == "1"
      
        last,first = field['a'].strip_trailing_punct.split(", ")
        if last && first
          resource.assert("[foaf:surname]", last)
          resource.assert("[foaf:givenname]", first.strip)
        end
      end
      if field['q']
        resource.assert("[dct:alternate]", field['q'].strip_leading_and_trailing_punct)
      end
      if field['u']
        resource.assert("[ov:affiliation]", field['u'].strip_trailing_punct)
      end
    elsif corporate.index(field.tag)
      resource.relate("[rdf:type]", "[foaf:Organization]")
      if field['u']
        resource.assert("[dct:description]", field['u'].strip_trailing_punct)
      end
    elsif field.tag == "720"
      if field.indicator1 == "1"
        resource.relate("[rdf:type]", "[foaf:Person]")
      else
        resource.relate("[rdf:type]", "[foaf:Agent]")
      end
    end
    resource.assert("[foaf:name]", field['a'].strip_trailing_punct)
    if field['d']
      resource.assert("[dct:date]", field['d'])
    end
    identity.resource = resource
    identity
  end
  def self.path(datafield)
    personal = ["100","400", "600","696","700","790","796", "800","896"]
    corporate = ["110","410", "610", "697","710","791","797", "810", "897"]
    if personal.index(datafield.tag)
      return "people"
    elsif corporate.index(datafield.tag)
      return "organizations"
    elsif datafield.tag == "720"
      if datafield.indicator1 == "1"
        return "people"
      else
        return "agents"
      end
    end
  end
    
  def self.relations(field)
    
  end
end

=begin
  Beginning of actual code
  * Start by loading relation yaml file into hash object
  * then parse each record and look for tags that give relations
  * if relation tag have field 'e' or '4' put them in object relators
  * the
=end  
begin
  yaml = YAML.load_file('relation.yml')
rescue Errno::ENOENT
  relations = {}
  reader.each do | record |
    relators = record.find_all{|field| field.tag =~ /100|110|111|270|400|410|411|600|610|611|696|697|698|700|710|711|720|790|791|792|796|797|798|800|810|811|896|897|898/ && (field['e'] || field['4'])}
    relators.each do | relator |
      relator.subfields.each do | subfield |
        if subfield.code == 'e' && !["111","270","411","611","698","711","792","798","811","898"].index(relator.tag)
          relations[subfield.value.strip_trailing_punct] = nil
        end

        if subfield.code == "4"
          relations[subfield.value.strip_trailing_punct] = nil
        end
      end      
    end
  end
  fh = open('relation.yml', "w+")
  fh << relations.to_yaml
  fh.close
  exit
end

types = []

=begin
  The actual record processing
  * opens file handle 'output_file'
  * outputs standard rdfxml header
  * parses each Marc record through function to_rdf_resources and appends to instance variable @resources
  * parses each resource  through function to_rdfxml and appends to file output
=end
output = open(output_file, "w+")
output << "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
output << "<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\n"  

reader.each do | record |
	@resources = []
  types << record.class.to_s

  #next unless record.is_a?(MARC::VisualRecord)
  @resources += record.to_rdf_resources
	@resources.each do | resource |
	output << resource.to_rdfxml
	output << "\n"
	end
  i += 1
#  break if i > 1000
end

puts types.uniq.inspect   # prints out unique rdf types

output << "</rdf:RDF>"
output.close
