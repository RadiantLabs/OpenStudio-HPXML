# frozen_string_literal: true

require_relative '../resources/minitest_helper'
require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'fileutils'
require_relative '../measure.rb'
require_relative '../resources/util.rb'

class HPXMLtoOpenStudioSimControlsTest < MiniTest::Test
  def setup
    @root_path = File.absolute_path(File.join(File.dirname(__FILE__), '..', '..'))
    @sample_files_path = File.join(@root_path, 'workflow', 'sample_files')
    @tmp_hpxml_path = File.join(@sample_files_path, 'tmp.xml')
    @tmp_output_path = File.join(@sample_files_path, 'tmp_output')
    FileUtils.mkdir_p(@tmp_output_path)
  end

  def teardown
    File.delete(@tmp_hpxml_path) if File.exist? @tmp_hpxml_path
    FileUtils.rm_rf(@tmp_output_path)
  end

  def sample_files_dir
    return File.join(File.dirname(__FILE__), '..', '..', 'workflow', 'sample_files')
  end

  def test_default_schedules
    args_hash = {}
    args_hash['hpxml_path'] = File.absolute_path(File.join(sample_files_dir, 'base.xml'))
    model, hpxml = _test_measure(args_hash)

    schedule_constants = 9
    schedule_rulesets = 17
    schedule_fixed_intervals = 1
    schedule_files = 0

    assert_equal(schedule_constants, model.getScheduleColumns.size)
    assert_equal(schedule_rulesets, model.getScheduleRulesets.size)
    assert_equal(schedule_fixed_intervals, model.getScheduleFixedIntervals.size)
    assert_equal(schedule_files, model.getScheduleFiles.size)
    assert_equal(model.getSchedules.size, schedule_constants + schedule_rulesets + schedule_fixed_intervals + schedule_files)
  end

  def test_stochastic_schedules
    args_hash = {}
    args_hash['hpxml_path'] = File.absolute_path(File.join(sample_files_dir, 'base-schedules-detailed-stochastic.xml'))
    model, hpxml = _test_measure(args_hash)

    schedule_constants = 9
    schedule_rulesets = 5
    schedule_fixed_intervals = 1
    schedule_files = 13

    assert_equal(schedule_constants, model.getScheduleColumns.size)
    assert_equal(schedule_rulesets, model.getScheduleRulesets.size)
    assert_equal(schedule_fixed_intervals, model.getScheduleFixedIntervals.size)
    assert_equal(schedule_files, model.getScheduleFiles.size)
    assert_equal(model.getSchedules.size, schedule_constants + schedule_rulesets + schedule_fixed_intervals + schedule_files)

    schedule_file_names = []
    model.getScheduleFiles.each do |schedule_file|
      schedule_file_names << "#{schedule_file.name}"
    end
    assert(schedule_file_names.include?(ScheduleColumns.Occupants))
    assert(schedule_file_names.include?(ScheduleColumns.LightingInterior))
    assert(schedule_file_names.include?(ScheduleColumns.LightingExterior))
    assert(!schedule_file_names.include?(ScheduleColumns.LightingGarage))
    assert(!schedule_file_names.include?(ScheduleScheduleColumns.LightingExteriorHoliday))
    assert(schedule_file_names.include?(ScheduleColumns.CookingRange))
    assert(schedule_file_names.include?(ScheduleColumns.Refrigerator))
    assert(!schedule_file_names.include?(ScheduleColumns.ExtraRefrigerator))
    assert(!schedule_file_names.include?(ScheduleColumns.Freezer))
    assert(schedule_file_names.include?(ScheduleColumns.Dishwasher))
    assert(schedule_file_names.include?(ScheduleColumns.ClothesWasher))
    assert(schedule_file_names.include?(ScheduleColumns.ClothesDryer))
    assert(!schedule_file_names.include?(ScheduleColumns.CeilingFan))
    assert(schedule_file_names.include?(ScheduleColumns.PlugLoadsOther))
    assert(schedule_file_names.include?(ScheduleColumns.PlugLoadsTV))
    assert(!schedule_file_names.include?(ScheduleColumns.PlugLoadsVehicle))
    assert(!schedule_file_names.include?(ScheduleColumns.PlugLoadsWellPump))
    assert(!schedule_file_names.include?(ScheduleColumns.FuelLoadsGrill))
    assert(!schedule_file_names.include?(ScheduleColumns.FuelLoadsLighting))
    assert(!schedule_file_names.include?(ScheduleColumns.FuelLoadsFireplace))
    assert(!schedule_file_names.include?(ScheduleColumns.PoolPump))
    assert(!schedule_file_names.include?(ScheduleColumns.PoolHeater))
    assert(!schedule_file_names.include?(ScheduleColumns.HotTubPump))
    assert(!schedule_file_names.include?(ScheduleColumns.HotTubHeater))
    assert(schedule_file_names.include?(ScheduleColumns.HotWaterClothesWasher))
    assert(schedule_file_names.include?(ScheduleColumns.HotWaterDishwasher))
    assert(schedule_file_names.include?(ScheduleColumns.HotWaterFixtures))

    # add a pool
    hpxml.pools.add(id: 'Pool',
                    type: HPXML::TypeUnknown,
                    pump_type: HPXML::TypeUnknown,
                    pump_kwh_per_year: 2700,
                    heater_type: HPXML::HeaterTypeGas,
                    heater_load_units: HPXML::UnitsThermPerYear,
                    heater_load_value: 500)

    args_hash = {}
    args_hash['hpxml_path'] = File.absolute_path(@tmp_hpxml_path)
    XMLHelper.write_file(hpxml.to_oga, @tmp_hpxml_path)
    model, hpxml = _test_measure(args_hash)

    schedule_file_names = []
    model.getScheduleFiles.each do |schedule_file|
      schedule_file_names << "#{schedule_file.name}"
    end
    assert(schedule_file_names.include?(ScheduleColumns.PoolPump))
    assert(schedule_file_names.include?(ScheduleColumns.PoolHeater))
  end

  def test_stochastic_vacancy_schedules
    args_hash = {}
    args_hash['hpxml_path'] = File.absolute_path(File.join(sample_files_dir, 'base-schedules-detailed-stochastic-vacancy.xml'))
    model, hpxml = _test_measure(args_hash)

    schedule_constants = 9
    schedule_rulesets = 5
    schedule_fixed_intervals = 1
    schedule_files = 13

    assert_equal(schedule_constants, model.getScheduleColumns.size)
    assert_equal(schedule_rulesets, model.getScheduleRulesets.size)
    assert_equal(schedule_fixed_intervals, model.getScheduleFixedIntervals.size)
    assert_equal(schedule_files, model.getScheduleFiles.size)
    assert_equal(model.getSchedules.size, schedule_constants + schedule_rulesets + schedule_fixed_intervals + schedule_files)
  end

  def test_smooth_schedules
    args_hash = {}
    args_hash['hpxml_path'] = File.absolute_path(File.join(sample_files_dir, 'base-schedules-detailed-smooth.xml'))
    model, hpxml = _test_measure(args_hash)

    schedule_constants = 9
    schedule_rulesets = 5
    schedule_fixed_intervals = 1
    schedule_files = 13

    assert_equal(schedule_constants, model.getScheduleColumns.size)
    assert_equal(schedule_rulesets, model.getScheduleRulesets.size)
    assert_equal(schedule_fixed_intervals, model.getScheduleFixedIntervals.size)
    assert_equal(schedule_files, model.getScheduleFiles.size)
    assert_equal(model.getSchedules.size, schedule_constants + schedule_rulesets + schedule_fixed_intervals + schedule_files)
  end

  def _test_measure(args_hash)
    # create an instance of the measure
    measure = HPXMLtoOpenStudio.new

    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
    model = OpenStudio::Model::Model.new

    # get arguments
    args_hash['output_dir'] = 'tests'
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      if args_hash.has_key?(arg.name)
        assert(temp_arg_var.setValue(args_hash[arg.name]))
      end
      argument_map[arg.name] = temp_arg_var
    end

    # run the measure
    measure.run(model, runner, argument_map)
    result = runner.result

    # show the output
    show_output(result) unless result.value.valueName == 'Success'

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    hpxml = HPXML.new(hpxml_path: args_hash['hpxml_path'])

    File.delete(File.join(File.dirname(__FILE__), 'in.xml'))

    return model, hpxml
  end
end
