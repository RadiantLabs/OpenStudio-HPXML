# frozen_string_literal: true

require_relative '../resources/minitest_helper'
require 'openstudio'
require 'openstudio/ruleset/ShowRunnerOutput'
require 'minitest/autorun'
require 'fileutils'
require_relative '../measure.rb'
require_relative '../resources/util.rb'
require 'schematron-nokogiri'

class HPXMLtoOpenStudioSchematronTest < MiniTest::Test
  def before_setup
    @root_path = File.absolute_path(File.join(File.dirname(__FILE__), '..', '..'))
    @tmp_output_path = File.join(@root_path, 'workflow', 'sample_files', 'tmp_output')
    FileUtils.mkdir_p(@tmp_output_path)
    @tmp_hpxml_path = File.join(@tmp_output_path, 'tmp.xml')
  end
  
  def after_teardown
    FileUtils.rm_rf(@tmp_output_path)
  end

  def test_valid_sample_files
    sample_files_dir = File.absolute_path(File.join(@root_path, 'workflow', 'sample_files'))
    hpxmls = []
    Dir["#{sample_files_dir}/*.xml"].sort.each do |xml|
      hpxmls << File.absolute_path(xml)
    end
    hpxmls.each do |hpxml|
      _test_schematron_validation(hpxml)
    end
  end

  def test_invalid_files
    # TODO: Need to add more test cases
    expected_error_msgs = { '/HPXML/XMLTransactionHeaderInformation/XMLType' => "element 'XMLType' is REQUIRED",
                            '/HPXML/XMLTransactionHeaderInformation/XMLGeneratedBy' => "element 'XMLGeneratedBy' is REQUIRED",
                            '/HPXML/XMLTransactionHeaderInformation/CreatedDateAndTime' => "element 'CreatedDateAndTime' is REQUIRED",
                            '/HPXML/XMLTransactionHeaderInformation/Transaction' => "element 'Transaction' is REQUIRED",
                            '/HPXML/Building' => "element 'Building' is REQUIRED",
                            '/HPXML/Building/BuildingID' => "element 'BuildingID' is REQUIRED",
                            '/HPXML/Building/ProjectStatus/EventType' => "element 'ProjectStatus/EventType' is REQUIRED",
                          }
    
    expected_error_msgs.each do |key, value|
      hpxml_name = 'base.xml'
      hpxml = HPXML.new(hpxml_path: File.join(@root_path, 'workflow', 'sample_files', hpxml_name))
      hpxml_doc = hpxml.to_oga()
      XMLHelper.delete_element(hpxml_doc, key)
      XMLHelper.write_file(hpxml_doc, @tmp_hpxml_path)
      _test_schematron_validation(@tmp_hpxml_path, value)
    end
  end

  def _test_schematron_validation(hpxml_path, expected_error_msgs = nil)
    # load the schematron xml
    stron_doc = Nokogiri::XML File.open(File.join(@root_path, 'HPXMLtoOpenStudio', 'resources', 'EPvalidator.xml'))  # "/path/to/schema.stron"
    # make a schematron object
    stron = SchematronNokogiri::Schema.new stron_doc
    # load the xml document you wish to validate
    xml_doc = Nokogiri::XML File.open(hpxml_path)  # "/path/to/xml_document.xml"
    # validate it
    results = stron.validate xml_doc
    # print out the results
    if results.empty?
      assert_empty(results)
    else
      results.each do |error|
        assert_equal(expected_error_msgs, error[:message])
      end
    end
  end
end