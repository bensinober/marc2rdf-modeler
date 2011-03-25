#!/usr/bin/env ruby

require 'uri'
require 'builder'
require 'date'
require 'curies' # compact uris with prefixes


class RDFResource
=begin
     An object's instance variables are its attributes
     attr_reader reads in these 
     Curie.parse explodes uris from prefix:suffix 
=end
  attr_reader :uri, :namespaces, :modifiers
  def initialize(uri)
    Curie.add_prefixes! :frbr=>"http://vocab.org/frbr/core#", 
    :owl=>"http://www.w3.org/2002/07/owl#",
	:xsl=>"http://www.w3.org/1999/XSL/Transform",
	:xsd=>"http://www.w3.org/2001/XMLSchema#",
	:rdf=>"http://www.w3.org/1999/02/22-rdf-syntax-ns#",
	:rdfs=>"http://www.w3.org/2000/01/rdf-schema#",
	:foaf=>"http://xmlns.com/foaf/0.1/",
	:xfoaf=>"http://www.foafrealm.org/xfoaf/0.1/",
	:lingvoj=>"http://www.lingvoj.org/ontology#",
	:lexvo=>"http://lexvo.org/id/iso639-3/",
	:mm=>"http://musicbrainz.org/mm/mm-2.1#",
	:mo=>"http://purl.org/ontology/mo#",
	:dcmi=>"http://dublincore.org/documents/dcmi-terms/",
	:dcmitype=>"http://dublincore.org/documents/dcmi-type-vocabulary/",
	:skos=>"http://www.w3.org/2004/02/skos/core#",
	:geo=>"http://www.geonames.org/ontology#",
	:dct=>"http://purl.org/dc/elements/1.1/",
	:dc=>"http://purl.org/dc/elements/1.1/",
	:cc=>"http://web.resource.org/cc/",
	:marc21slim=>"http://www.loc.gov/MARC21/slim",
	:bibo=>"http://purl.org/ontology/bibo/",
	:pode=>"http://www.bibpode.no/vocabulary#",
	:ff=>"http://www.bibpode.no/ff/",
	:lf=>"http://www.bibpode.no/lf/",
	:sublima=>"http://xmlns.computas.com/sublima#",
	:deweyClass=>"http://dewey.info/class/",
	:owl2xml=>"http://www.w3.org/2006/12/owl2-xml#",
	:movie=>"http://data.linkedmdb.org/resource/movie/",
	:rda=>"http://RDVocab.info/Elements/", 
    :cat=>"http://schema.talis.com/2009/catalontology/",
    :rdfs=>"http://www.w3.org/2000/01/rdf-schema#", 
    :ov=>"http://open.vocab.org/terms/", 
    :event=>"http://purl.org/NET/c4dm/event.owl#",
    :role=>"http://RDVocab.info/roles/"
    
    if uri.could_be_a_safe_curie?
      @uri = Curie.parse uri
    else
      @uri = uri
    end
    @namespaces = ['http://www.w3.org/1999/02/22-rdf-syntax-ns#']

    @modifiers = {}
  end

=begin  
     assert function 
     takes: predicate, object, type and lang
     parses out rdf predicate and object with ns prefixes 
=end
  def assert(predicate, object, type=nil, lang=nil)
    if predicate.could_be_a_safe_curie?
      uri = URI.parse(Curie.parse predicate)
    else
      uri = URI.parse(predicate)
    end
    ns = nil
    elem = nil
    if uri.fragment
      ns, elem = uri.to_s.split('#')
      ns << '#'
    else
      elem = uri.path.split('/').last
      ns = uri.to_s.sub(/#{elem}$/, '')
    end
    attr_name = ''
    if i = @namespaces.index(ns)
      attr_name = "n#{i}_#{elem}"
    else
      @namespaces << ns
      attr_name = "n#{@namespaces.index(ns)}_#{elem}"
    end
    
    # if type is not given, value is same as object
    unless type
      val = object
    # if type is given, object is converted according to type
    else
    
      @modifiers[object.object_id] ||={}
      @modifiers[object.object_id][:type] = type   # fallback to ...
      val = case type
      when 'http://www.w3.org/2001/XMLSchema#dateTime' then DateTime.parse(object)
      when 'http://www.w3.org/2001/XMLSchema#date' then Date.parse(object)
      when 'http://www.w3.org/2001/XMLSchema#int' then object.to_i
      when 'http://www.w3.org/2001/XMLSchema#string' then object.to_s
      when 'http://www.w3.org/2001/XMLSchema#boolean'
        if object.downcase == 'true' || object == '1'
          true
        else
          false
        end
      else
        object
      end
    end

    # if lang is given, object is converted according to type
    if lang
      @modifiers[object.object_id] ||={}
      @modifiers[val.object_id][:language] = lang  
    end
    if self.instance_variable_defined?("@#{attr_name}")
      unless self.instance_variable_get("@#{attr_name}").is_a?(Array)
        att = self.instance_variable_get("@#{attr_name}")
        self.instance_variable_set("@#{attr_name}", [att])
      end
      self.instance_variable_get("@#{attr_name}") << val
    else
      self.instance_variable_set("@#{attr_name}", val)
    end
  end

=begin  
     relate function 
     takes: predicate, resource
     parses out new rdf relation between predicate resource uri
=end
  def relate(predicate, resource)
    self.assert(predicate, self.class.new(resource))
  end

=begin  
     to_rdfxml function 
     * creates doc object with xml markup
     * parses object to rdf xml namespaces as ns1, ns2, etc
     * parses out each rdf object with RDF description and about
     * 
=end
  def to_rdfxml
    doc = Builder::XmlMarkup.new
    xmlns = {}
    i = 1
    @namespaces.each do | ns |
      next if ns == 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'
      xmlns["xmlns:n#{i}"] = ns
      i += 1
    end
    doc.rdf :Description,xmlns.merge({'rdf:about'=>uri}) do | rdf |
      self.instance_variables.each do | ivar |
        next unless ivar =~ /^@n[0-9]*_/
        # fix: must cast ivar as string before split!
        prefix, tag = ivar.to_s.split("_", 2)
        attrs = {}
        curr_attr = self.instance_variable_get("#{ivar}")
        prefix.sub!(/^@/,'')
        prefix = 'rdf' if prefix == 'n0'
        unless curr_attr.is_a?(Array)
          curr_attr = [curr_attr]
        end
        curr_attr.each do | val |
          if val.is_a?(RDFResource)           # is value RDFResource an array? 
            attrs['rdf:resource'] = val.uri   # then it's an uri
          end
          if @modifiers[val.object_id]        # do I have object literal modifiers (language or xsd:type)?
            if @modifiers[val.object_id][:language]
              attrs['xml:lang'] = @modifiers[val.object_id][:language]
            end
            if @modifiers[val.object_id][:type]
              attrs['rdf:datatype'] = @modifiers[val.object_id][:type]
            end          
          end
          unless attrs['rdf:resource']                  # if object is uri append tag with value
            rdf.tag!("#{prefix}:#{tag}", attrs, val)
          else
            rdf.tag!("#{prefix}:#{tag}", attrs)
          end
        end
      end
    end
    doc.target!
  end
  
end
