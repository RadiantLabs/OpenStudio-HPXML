# frozen_string_literal: true

require 'oga'
require_relative '../../HPXMLtoOpenStudio/resources/utility_bills'
require_relative '../../HPXMLtoOpenStudio/resources/constants'
require_relative '../../HPXMLtoOpenStudio/resources/energyplus'
require_relative '../../HPXMLtoOpenStudio/resources/hpxml'
require_relative '../../HPXMLtoOpenStudio/resources/hpxml_defaults'
require_relative '../../HPXMLtoOpenStudio/resources/minitest_helper'
require_relative '../../HPXMLtoOpenStudio/resources/schedules'
require_relative '../../HPXMLtoOpenStudio/resources/unit_conversions'
require_relative '../../HPXMLtoOpenStudio/resources/xmlhelper'
require_relative '../resources/util.rb'
require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require_relative '../measure.rb'
require 'csv'

class ReportUtilityBillsTest < MiniTest::Test
  # BEopt 2.9.0.0:
  # - Standard, New Construction, Single-Family Detached
  # - 600 sq ft (30 x 20)
  # - EPW Location: USA_CO_Denver.Intl.AP.725650_TMY3.epw
  # - Cooking Range: Propane
  # - Water Heater: Oil Standard
  # - PV System: None, 1.0 kW, 10.0 kW
  # - Timestep: 60 min
  # - User-Specified rates (calculated using default value):
  #   - Electricity: 0.1195179675994109 $/kWh
  #   - Natural Gas: 0.7734017611590879 $/therm
  #   - Fuel Oil: 3.495346153846154 $/gal
  #   - Propane: 2.4532692307692305 $/gal
  # - Sample Tiered Rate
  #   - Tier 1: 150 Max kWh
  #   - Tier 2: 300 Max kWh
  # - Sample Tiered Time-of-Use Rate
  #   - Tier 1: 150 Max kWh (Period 1 and 2)
  #   - Tier 2: 300 Max kWh (Period 2)
  # - All other options left at default values
  # Then retrieve 1.csv from output folder, copy it, rename it

  def setup
    @args_hash = {}

    # From BEopt Output screen (Utility Bills $/yr)
    @expected_bills = {
      'Test: Electricity: Fixed ($)' => 96,
      'Test: Electricity: Marginal ($)' => 632,
      'Test: Electricity: PV Credit ($)' => 0,
      'Test: Natural Gas: Fixed ($)' => 96,
      'Test: Natural Gas: Marginal ($)' => 149,
      'Test: Fuel Oil: Fixed ($)' => 0,
      'Test: Fuel Oil: Marginal ($)' => 462,
      'Test: Propane: Fixed ($)' => 0,
      'Test: Propane: Marginal ($)' => 76,
      'Test: Coal: Fixed ($)' => 0,
      'Test: Coal: Marginal ($)' => 0,
      'Test: Wood Cord: Fixed ($)' => 0,
      'Test: Wood Cord: Marginal ($)' => 0,
      'Test: Wood Pellets: Fixed ($)' => 0,
      'Test: Wood Pellets: Marginal ($)' => 0
    }

    @measure = ReportUtilityBills.new
    @hpxml_path = File.join(File.dirname(__FILE__), '../../workflow/sample_files/base-pv.xml')
    @hpxml = HPXML.new(hpxml_path: @hpxml_path)
    @hpxml.header.utility_bill_scenarios.clear
    @hpxml.header.utility_bill_scenarios.add(name: 'Test',
                                             elec_fixed_charge: 8.0,
                                             natural_gas_fixed_charge: 8.0,
                                             propane_marginal_rate: 2.4532692307692305,
                                             fuel_oil_marginal_rate: 3.495346153846154)

    HPXMLDefaults.apply_header(@hpxml, nil)
    HPXMLDefaults.apply_utility_bill_scenarios(nil, @hpxml)

    @root_path = File.absolute_path(File.join(File.dirname(__FILE__), '..', '..'))
    @sample_files_path = File.join(@root_path, 'workflow', 'sample_files')
    @tmp_hpxml_path = File.join(@sample_files_path, 'tmp.xml')
    @bills_csv = File.join(File.dirname(__FILE__), 'results_bills.csv')
  end

  def teardown
    File.delete(@tmp_hpxml_path) if File.exist? @tmp_hpxml_path
    File.delete(@bills_csv) if File.exist? @bills_csv
  end

  # Simple Calculations

  def test_simple_calculations_pv_none
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_None.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, [], utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_simple_calculations_pv_1kW_net_metering_user_specified_excess_rate
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: PV Credit ($)'] = -177
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_simple_calculations_pv_10kW_net_metering_user_specified_excess_rate
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_10kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: PV Credit ($)'] = -920
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_simple_calculations_pv_10kW_net_metering_retail_excess_rate
    @hpxml.header.utility_bill_scenarios[-1].pv_net_metering_annual_excess_sellback_rate_type = HPXML::PVAnnualExcessSellbackRateTypeRetailElectricityCost
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_10kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: PV Credit ($)'] = -1777
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_simple_calculations_pv_1kW_feed_in_tariff
    @hpxml.header.utility_bill_scenarios[-1].pv_compensation_type = HPXML::PVCompensationTypeFeedInTariff
    @hpxml.header.utility_bill_scenarios[-1].pv_feed_in_tariff_rate = 0.12
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: PV Credit ($)'] = -178
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_simple_calculations_pv_10kW_feed_in_tariff
    @hpxml.header.utility_bill_scenarios[-1].pv_compensation_type = HPXML::PVCompensationTypeFeedInTariff
    @hpxml.header.utility_bill_scenarios[-1].pv_feed_in_tariff_rate = 0.12
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_10kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: PV Credit ($)'] = -1785
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_simple_calculations_pv_1kW_grid_fee_dollars_per_kW
    @hpxml.header.utility_bill_scenarios[-1].pv_monthly_grid_connection_fee_dollars_per_kw = 2.50
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 126
      @expected_bills['Test: Electricity: PV Credit ($)'] = -177
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_simple_calculations_pv_1kW_grid_fee_dollars
    @hpxml.header.utility_bill_scenarios[-1].pv_monthly_grid_connection_fee_dollars = 7.50
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 186
      @expected_bills['Test: Electricity: PV Credit ($)'] = -177
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_workflow_wood_cord
    @args_hash['hpxml_path'] = File.absolute_path(@tmp_hpxml_path)
    hpxml = HPXML.new(hpxml_path: File.join(@sample_files_path, 'base-hvac-furnace-wood-only.xml'))
    hpxml.header.utility_bill_scenarios.add(name: 'Test 1', wood_marginal_rate: 0.015)
    hpxml.header.utility_bill_scenarios.add(name: 'Test 2', wood_marginal_rate: 0.03)
    XMLHelper.write_file(hpxml.to_oga, @tmp_hpxml_path)
    bills_csv = _test_measure()
    assert(File.exist?(bills_csv))
    actual_bills = _get_actual_bills(bills_csv)
    expected_val = actual_bills['Test 1: Wood Cord: Total ($)']
    assert_in_delta(expected_val * 2, actual_bills['Test 2: Wood Cord: Total ($)'], 1)
  end

  def test_workflow_wood_pellets
    @args_hash['hpxml_path'] = File.absolute_path(@tmp_hpxml_path)
    hpxml = HPXML.new(hpxml_path: File.join(@sample_files_path, 'base-hvac-stove-wood-pellets-only.xml'))
    hpxml.header.utility_bill_scenarios.add(name: 'Test 1', wood_pellets_marginal_rate: 0.02)
    hpxml.header.utility_bill_scenarios.add(name: 'Test 2', wood_pellets_marginal_rate: 0.01)
    XMLHelper.write_file(hpxml.to_oga, @tmp_hpxml_path)
    bills_csv = _test_measure()
    assert(File.exist?(bills_csv))
    actual_bills = _get_actual_bills(bills_csv)
    expected_val = actual_bills['Test 1: Wood Pellets: Total ($)']
    assert_in_delta(expected_val / 2, actual_bills['Test 2: Wood Pellets: Total ($)'], 1)
  end

  def test_workflow_coal
    @args_hash['hpxml_path'] = File.absolute_path(@tmp_hpxml_path)
    hpxml = HPXML.new(hpxml_path: File.join(@sample_files_path, 'base-hvac-furnace-coal-only.xml'))
    hpxml.header.utility_bill_scenarios.add(name: 'Test 1', coal_marginal_rate: 0.05)
    hpxml.header.utility_bill_scenarios.add(name: 'Test 2', coal_marginal_rate: 0.1)
    hpxml.header.utility_bill_scenarios.add(name: 'Test 3', coal_marginal_rate: 0.025)
    XMLHelper.write_file(hpxml.to_oga, @tmp_hpxml_path)
    bills_csv = _test_measure()
    assert(File.exist?(bills_csv))
    actual_bills = _get_actual_bills(bills_csv)
    expected_val = actual_bills['Test 1: Coal: Total ($)']
    assert_in_delta(expected_val * 2, actual_bills['Test 2: Coal: Total ($)'], 1)
    assert_in_delta(expected_val / 2, actual_bills['Test 3: Coal: Total ($)'], 1)
  end

  def test_workflow_leap_year
    @args_hash['hpxml_path'] = File.absolute_path(@tmp_hpxml_path)
    hpxml = HPXML.new(hpxml_path: File.join(@sample_files_path, 'base-location-AMY-2012.xml'))
    XMLHelper.write_file(hpxml.to_oga, @tmp_hpxml_path)
    bills_csv = _test_measure()
    assert(File.exist?(bills_csv))
    actual_bills = _get_actual_bills(bills_csv)
    assert_operator(actual_bills['Bills: Total ($)'], :>, 0)
  end

  def test_workflow_semi_annual_run_period
    @args_hash['hpxml_path'] = File.absolute_path(@tmp_hpxml_path)
    hpxml = HPXML.new(hpxml_path: File.join(@sample_files_path, 'base-simcontrol-runperiod-1-month.xml'))
    XMLHelper.write_file(hpxml.to_oga, @tmp_hpxml_path)
    bills_csv = _test_measure()
    assert(File.exist?(bills_csv))
    actual_bills = _get_actual_bills(bills_csv)
    assert_operator(actual_bills['Bills: Total ($)'], :>, 0)
  end

  def test_workflow_no_bill_scenarios
    @args_hash['hpxml_path'] = File.absolute_path(@tmp_hpxml_path)
    hpxml = HPXML.new(hpxml_path: File.join(@sample_files_path, 'base-misc-bills-none.xml'))
    XMLHelper.write_file(hpxml.to_oga, @tmp_hpxml_path)
    bills_csv = _test_measure()
    assert(!File.exist?(bills_csv))
  end

  def test_workflow_detailed_calculations
    @args_hash['hpxml_path'] = File.absolute_path(@tmp_hpxml_path)
    hpxml = HPXML.new(hpxml_path: File.join(@sample_files_path, 'base.xml'))
    hpxml.header.utility_bill_scenarios.add(name: 'Test 1', elec_tariff_filepath: '../../ReportUtilityBills/resources/rates/5a0b28045457a3ea2aca608e.json')
    XMLHelper.write_file(hpxml.to_oga, @tmp_hpxml_path)
    bills_csv = _test_measure()
    assert(File.exist?(bills_csv))
    actual_bills = _get_actual_bills(bills_csv)
    assert_operator(actual_bills['Test 1: Total ($)'], :>, 0)
  end

  def test_auto_marginal_rate
    fuel_types = [HPXML::FuelTypeElectricity, HPXML::FuelTypeNaturalGas, HPXML::FuelTypeOil, HPXML::FuelTypePropane]

    # Check that we can successfully look up "auto" rates for every state
    # and every fuel type.
    Constants.StateCodesMap.keys.each do |state_code|
      fuel_types.each do |fuel_type|
        flatratebuy, _ = UtilityBills.get_rates_from_eia_data(nil, state_code, fuel_type, 0)
        refute_nil(flatratebuy)
      end
    end

    # Check that we can successfully look up "auto" rates for the US too.
    fuel_types.each do |fuel_type|
      flatratebuy, _ = UtilityBills.get_rates_from_eia_data(nil, 'US', fuel_type, 0)
      refute_nil(flatratebuy)
    end

    # Check that any other state code is gracefully handled (no error)
    fuel_types.each do |fuel_type|
      UtilityBills.get_rates_from_eia_data(nil, 'XX', fuel_type, 0)
    end
  end

  def test_warning_region
    @args_hash['hpxml_path'] = File.absolute_path(@tmp_hpxml_path)
    hpxml = HPXML.new(hpxml_path: File.join(@sample_files_path, 'base-appliances-oil-location-miami-fl.xml'))
    XMLHelper.write_file(hpxml.to_oga, @tmp_hpxml_path)
    expected_warnings = ['Could not find state average fuel oil rate based on Florida; using region (PADD 1C) average.']
    bills_csv = _test_measure(expected_warnings: expected_warnings)
    assert(File.exist?(bills_csv))
  end

  def test_warning_national
    @args_hash['hpxml_path'] = File.absolute_path(@tmp_hpxml_path)
    hpxml = HPXML.new(hpxml_path: File.join(@sample_files_path, 'base-appliances-propane-location-portland-or.xml'))
    XMLHelper.write_file(hpxml.to_oga, @tmp_hpxml_path)
    expected_warnings = ['Could not find state average propane rate based on Oregon; using national average.']
    bills_csv = _test_measure(expected_warnings: expected_warnings)
    assert(File.exist?(bills_csv))
  end

  def test_warning_dse
    @args_hash['hpxml_path'] = File.absolute_path(@tmp_hpxml_path)
    hpxml = HPXML.new(hpxml_path: File.join(@sample_files_path, 'base-hvac-dse.xml'))
    XMLHelper.write_file(hpxml.to_oga, @tmp_hpxml_path)
    expected_warnings = ['DSE is not currently supported when calculating utility bills.']
    bills_csv = _test_measure(expected_warnings: expected_warnings)
    assert(!File.exist?(bills_csv))
  end

  def test_warning_no_rates
    @args_hash['hpxml_path'] = File.absolute_path(@tmp_hpxml_path)
    hpxml = HPXML.new(hpxml_path: File.join(@sample_files_path, 'base-location-capetown-zaf.xml'))
    XMLHelper.write_file(hpxml.to_oga, @tmp_hpxml_path)
    expected_warnings = ['Could not find a marginal Electricity rate.', 'Could not find a marginal Natural Gas rate.']
    bills_csv = _test_measure(expected_warnings: expected_warnings)
    assert(!File.exist?(bills_csv))
  end

  def test_warning_demand_charges
    @args_hash['hpxml_path'] = File.absolute_path(@tmp_hpxml_path)
    hpxml = HPXML.new(hpxml_path: File.join(@sample_files_path, 'base.xml'))
    hpxml.header.utility_bill_scenarios.add(name: 'Test 1', elec_tariff_filepath: '../../ReportUtilityBills/resources/rates/539f6aacec4f024411ec92ab.json')
    XMLHelper.write_file(hpxml.to_oga, @tmp_hpxml_path)
    expected_warnings = ['Demand charges are not currently supported when calculating detailed utility bills.']
    bills_csv = _test_measure(expected_warnings: expected_warnings)
    assert(File.exist?(bills_csv))
  end

  def test_monthly_prorate
    # Test begin_month == end_month
    header = HPXML::Header.new(nil)
    header.sim_begin_month = 3
    header.sim_begin_day = 5
    header.sim_end_month = 3
    header.sim_end_day = 20
    header.sim_calendar_year = 2002
    assert_equal(0.0, CalculateUtilityBill.calculate_monthly_prorate(header, 2))
    assert_equal((20 - 5 + 1) / 31.0, CalculateUtilityBill.calculate_monthly_prorate(header, 3))
    assert_equal(0.0, CalculateUtilityBill.calculate_monthly_prorate(header, 4))

    # Test begin_month != end_month
    header = HPXML::Header.new(nil)
    header.sim_begin_month = 2
    header.sim_begin_day = 10
    header.sim_end_month = 4
    header.sim_end_day = 10
    header.sim_calendar_year = 2002
    assert_equal(0.0, CalculateUtilityBill.calculate_monthly_prorate(header, 1))
    assert_equal((28 - 10 + 1) / 28.0, CalculateUtilityBill.calculate_monthly_prorate(header, 2))
    assert_equal(1.0, CalculateUtilityBill.calculate_monthly_prorate(header, 3))
    assert_equal(10 / 30.0, CalculateUtilityBill.calculate_monthly_prorate(header, 4))
    assert_equal(0.0, CalculateUtilityBill.calculate_monthly_prorate(header, 5))
  end

  # Detailed Calculations

  # Tiered

  def test_detailed_calculations_sample_tiered_pv_none
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Tiered Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_None.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 580
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tiered_pv_1kW_net_metering_user_specified_excess_rate
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Tiered Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 580
      @expected_bills['Test: Electricity: PV Credit ($)'] = -190
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tiered_pv_10kW_net_metering_user_specified_excess_rate
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Tiered Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_10kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 580
      @expected_bills['Test: Electricity: PV Credit ($)'] = -580
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tiered_pv_10kW_net_metering_retail_excess_rate
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Tiered Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_net_metering_annual_excess_sellback_rate_type = HPXML::PVAnnualExcessSellbackRateTypeRetailElectricityCost
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_10kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 580
      @expected_bills['Test: Electricity: PV Credit ($)'] = -1443
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tiered_pv_1kW_feed_in_tariff
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Tiered Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_compensation_type = HPXML::PVCompensationTypeFeedInTariff
    @hpxml.header.utility_bill_scenarios[-1].pv_feed_in_tariff_rate = 0.12
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 580
      @expected_bills['Test: Electricity: PV Credit ($)'] = -178
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tiered_pv_10kW_feed_in_tariff
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Tiered Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_compensation_type = HPXML::PVCompensationTypeFeedInTariff
    @hpxml.header.utility_bill_scenarios[-1].pv_feed_in_tariff_rate = 0.12
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_10kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 580
      @expected_bills['Test: Electricity: PV Credit ($)'] = -1785
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tiered_pv_1kW_grid_fee_dollars_per_kW
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Tiered Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_monthly_grid_connection_fee_dollars_per_kw = 2.50
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 138
      @expected_bills['Test: Electricity: Marginal ($)'] = 580
      @expected_bills['Test: Electricity: PV Credit ($)'] = -190
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tiered_pv_1kW_grid_fee_dollars
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Tiered Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_monthly_grid_connection_fee_dollars = 7.50
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 198
      @expected_bills['Test: Electricity: Marginal ($)'] = 580
      @expected_bills['Test: Electricity: PV Credit ($)'] = -190
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  # Time-of-Use

  def test_detailed_calculations_sample_tou_pv_none
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Time-of-Use Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_None.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 393
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tou_pv_1kW_net_metering_user_specified_excess_rate
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Time-of-Use Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 393
      @expected_bills['Test: Electricity: PV Credit ($)'] = -112
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tou_pv_10kW_net_metering_user_specified_excess_rate
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Time-of-Use Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_10kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 393
      @expected_bills['Test: Electricity: PV Credit ($)'] = -393
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tou_pv_10kW_net_metering_retail_excess_rate
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Time-of-Use Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_net_metering_annual_excess_sellback_rate_type = HPXML::PVAnnualExcessSellbackRateTypeRetailElectricityCost
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_10kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 393
      @expected_bills['Test: Electricity: PV Credit ($)'] = -1127
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tou_pv_1kW_feed_in_tariff
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Time-of-Use Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_compensation_type = HPXML::PVCompensationTypeFeedInTariff
    @hpxml.header.utility_bill_scenarios[-1].pv_feed_in_tariff_rate = 0.12
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 393
      @expected_bills['Test: Electricity: PV Credit ($)'] = -178
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tou_pv_10kW_feed_in_tariff
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Time-of-Use Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_compensation_type = HPXML::PVCompensationTypeFeedInTariff
    @hpxml.header.utility_bill_scenarios[-1].pv_feed_in_tariff_rate = 0.12
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_10kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 393
      @expected_bills['Test: Electricity: PV Credit ($)'] = -1785
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tou_pv_1kW_grid_fee_dollars_per_kW
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Time-of-Use Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_monthly_grid_connection_fee_dollars_per_kw = 2.50
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 138
      @expected_bills['Test: Electricity: Marginal ($)'] = 393
      @expected_bills['Test: Electricity: PV Credit ($)'] = -112
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tou_pv_1kW_grid_fee_dollars
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Time-of-Use Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_monthly_grid_connection_fee_dollars = 7.50
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 198
      @expected_bills['Test: Electricity: Marginal ($)'] = 393
      @expected_bills['Test: Electricity: PV Credit ($)'] = -112
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  # Tiered and Time-of-Use

  def test_detailed_calculations_sample_tiered_tou_pv_none
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Tiered Time-of-Use Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_None.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 377
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tiered_tou_pv_1kW_net_metering_user_specified_excess_rate
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Tiered Time-of-Use Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 377
      @expected_bills['Test: Electricity: PV Credit ($)'] = -108
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tiered_tou_pv_10kW_net_metering_user_specified_excess_rate
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Tiered Time-of-Use Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_10kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 377
      @expected_bills['Test: Electricity: PV Credit ($)'] = -377
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tiered_tou_pv_10kW_net_metering_retail_excess_rate
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Tiered Time-of-Use Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_net_metering_annual_excess_sellback_rate_type = HPXML::PVAnnualExcessSellbackRateTypeRetailElectricityCost
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_10kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 377
      @expected_bills['Test: Electricity: PV Credit ($)'] = -377
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tiered_tou_pv_1kW_feed_in_tariff
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Tiered Time-of-Use Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_compensation_type = HPXML::PVCompensationTypeFeedInTariff
    @hpxml.header.utility_bill_scenarios[-1].pv_feed_in_tariff_rate = 0.12
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 377
      @expected_bills['Test: Electricity: PV Credit ($)'] = -178
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tiered_tou_pv_10kW_feed_in_tariff
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Tiered Time-of-Use Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_compensation_type = HPXML::PVCompensationTypeFeedInTariff
    @hpxml.header.utility_bill_scenarios[-1].pv_feed_in_tariff_rate = 0.12
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_10kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 377
      @expected_bills['Test: Electricity: PV Credit ($)'] = -1785
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tiered_tou_pv_1kW_grid_fee_dollars_per_kW
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Tiered Time-of-Use Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_monthly_grid_connection_fee_dollars_per_kw = 2.50
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 138
      @expected_bills['Test: Electricity: Marginal ($)'] = 377
      @expected_bills['Test: Electricity: PV Credit ($)'] = -108
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_tiered_tou_pv_1kW_grid_fee_dollars
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Tiered Time-of-Use Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_monthly_grid_connection_fee_dollars = 7.50
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 198
      @expected_bills['Test: Electricity: Marginal ($)'] = 377
      @expected_bills['Test: Electricity: PV Credit ($)'] = -108
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  # Real-time Pricing

  def test_detailed_calculations_sample_real_time_pricing_pv_none
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Real-Time Pricing Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_None.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 354
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_real_time_pricing_pv_1kW_net_metering_user_specified_excess_rate
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Real-Time Pricing Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 354
      @expected_bills['Test: Electricity: PV Credit ($)'] = -106 # 107
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_real_time_pricing_pv_10kW_net_metering_user_specified_excess_rate
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Real-Time Pricing Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_10kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 354
      @expected_bills['Test: Electricity: PV Credit ($)'] = -641 # 642
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_real_time_pricing_pv_10kW_net_metering_retail_excess_rate
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Real-Time Pricing Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_net_metering_annual_excess_sellback_rate_type = HPXML::PVAnnualExcessSellbackRateTypeRetailElectricityCost
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_10kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 354
      @expected_bills['Test: Electricity: PV Credit ($)'] = -1060 # 1075
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_real_time_pricing_pv_1kW_feed_in_tariff
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Real-Time Pricing Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_compensation_type = HPXML::PVCompensationTypeFeedInTariff
    @hpxml.header.utility_bill_scenarios[-1].pv_feed_in_tariff_rate = 0.12
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 354
      @expected_bills['Test: Electricity: PV Credit ($)'] = -178
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_real_time_pricing_pv_10kW_feed_in_tariff
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Real-Time Pricing Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_compensation_type = HPXML::PVCompensationTypeFeedInTariff
    @hpxml.header.utility_bill_scenarios[-1].pv_feed_in_tariff_rate = 0.12
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 10000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_10kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 108
      @expected_bills['Test: Electricity: Marginal ($)'] = 354
      @expected_bills['Test: Electricity: PV Credit ($)'] = -1785
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_real_time_pricing_pv_1kW_grid_fee_dollars_per_kW
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Real-Time Pricing Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_monthly_grid_connection_fee_dollars_per_kw = 2.50
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 138
      @expected_bills['Test: Electricity: Marginal ($)'] = 354
      @expected_bills['Test: Electricity: PV Credit ($)'] = -106 # 107
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def test_detailed_calculations_sample_real_time_pricing_pv_1kW_grid_fee_dollars
    @hpxml.header.utility_bill_scenarios[-1].elec_tariff_filepath = '../../ReportUtilityBills/resources/Data/SampleRates/Sample Real-Time Pricing Rate.json'
    @hpxml.header.utility_bill_scenarios[-1].elec_fixed_charge = nil
    @hpxml.header.utility_bill_scenarios[-1].elec_marginal_rate = nil
    @hpxml.header.utility_bill_scenarios[-1].pv_monthly_grid_connection_fee_dollars = 7.50
    @hpxml.pv_systems.each { |pv_system| pv_system.max_power_output = 1000.0 / @hpxml.pv_systems.size }
    @hpxml.header.utility_bill_scenarios.each do |utility_bill_scenario|
      fuels = _load_timeseries('../tests/PV_1kW.csv', utility_bill_scenario)
      utility_rates, utility_bills = @measure.setup_utility_outputs()
      _bill_calcs(fuels, utility_rates, utility_bills, @hpxml.header, @hpxml.pv_systems, utility_bill_scenario)
      assert(File.exist?(@bills_csv))
      actual_bills = _get_actual_bills(@bills_csv)
      @expected_bills['Test: Electricity: Fixed ($)'] = 198
      @expected_bills['Test: Electricity: Marginal ($)'] = 354
      @expected_bills['Test: Electricity: PV Credit ($)'] = -106 # 107
      expected_bills = _get_expected_bills(@expected_bills)
      _check_bills(expected_bills, actual_bills)
    end
  end

  def _get_expected_bills(expected_bills)
    expected_bills['Test: Electricity: Total ($)'] = expected_bills['Test: Electricity: Fixed ($)'] + expected_bills['Test: Electricity: Marginal ($)'] + expected_bills['Test: Electricity: PV Credit ($)']
    expected_bills['Test: Natural Gas: Total ($)'] = expected_bills['Test: Natural Gas: Fixed ($)'] + expected_bills['Test: Natural Gas: Marginal ($)']
    expected_bills['Test: Fuel Oil: Total ($)'] = expected_bills['Test: Fuel Oil: Fixed ($)'] + expected_bills['Test: Fuel Oil: Marginal ($)']
    expected_bills['Test: Propane: Total ($)'] = expected_bills['Test: Propane: Fixed ($)'] + expected_bills['Test: Propane: Marginal ($)']
    expected_bills['Test: Coal: Total ($)'] = expected_bills['Test: Coal: Fixed ($)'] + expected_bills['Test: Coal: Marginal ($)']
    expected_bills['Test: Wood Cord: Total ($)'] = expected_bills['Test: Wood Cord: Fixed ($)'] + expected_bills['Test: Wood Cord: Marginal ($)']
    expected_bills['Test: Wood Pellets: Total ($)'] = expected_bills['Test: Wood Pellets: Fixed ($)'] + expected_bills['Test: Wood Pellets: Marginal ($)']
    expected_bills['Test: Total ($)'] = expected_bills['Test: Electricity: Total ($)'] + expected_bills['Test: Natural Gas: Total ($)'] + expected_bills['Test: Fuel Oil: Total ($)'] + expected_bills['Test: Propane: Total ($)'] + expected_bills['Test: Wood Cord: Total ($)'] + expected_bills['Test: Wood Pellets: Total ($)'] + expected_bills['Test: Coal: Total ($)']
    return expected_bills
  end

  def _check_bills(expected_bills, actual_bills)
    bills = expected_bills.keys | actual_bills.keys
    bills.each do |bill|
      assert(expected_bills.keys.include?(bill))
      if expected_bills[bill] != 0
        assert(actual_bills.keys.include?(bill))
        assert_in_delta(expected_bills[bill], actual_bills[bill], 1) # within a dollar
      end
    end
  end

  def _get_actual_bills(bills_csv)
    actual_bills = {}
    File.readlines(bills_csv).each do |line|
      next if line.strip.empty?

      key, value = line.split(',').map { |x| x.strip }
      actual_bills[key] = Float(value)
    end
    return actual_bills
  end

  def _load_timeseries(path, utility_bill_scenario)
    fuels = @measure.setup_fuel_outputs()

    columns = CSV.read(File.join(File.dirname(__FILE__), path)).transpose
    columns.each do |col|
      col_name = col[0]
      next if col_name == 'Date/Time'

      values = col[1..-1].map { |v| Float(v) }

      if col_name == 'ELECTRICITY:UNIT_1 [J](Hourly)'
        fuel = fuels[[FT::Elec, false]]
        unit_conv = UnitConversions.convert(1.0, 'J', fuel.units)
        fuel.timeseries = values.map { |v| v * unit_conv }
      elsif col_name == 'GAS:UNIT_1 [J](Hourly)'
        fuel = fuels[[FT::Gas, false]]
        unit_conv = UnitConversions.convert(1.0, 'J', fuel.units)
        fuel.timeseries = values.map { |v| v * unit_conv }
      elsif col_name == 'Appl_1:ExteriorEquipment:Propane [J](Hourly)'
        fuel = fuels[[FT::Propane, false]]
        unit_conv = UnitConversions.convert(1.0, 'J', fuel.units) / 91.6
        fuel.timeseries = values.map { |v| v * unit_conv }
      elsif col_name == 'FUELOIL:UNIT_1 [m3](Hourly)'
        fuel = fuels[[FT::Oil, false]]
        unit_conv = UnitConversions.convert(1.0, 'm^3', 'gal')
        fuel.timeseries = values.map { |v| v * unit_conv }
      elsif col_name == 'PV:ELECTRICITY_1 [J](Hourly) '
        fuel = fuels[[FT::Elec, true]]
        unit_conv = UnitConversions.convert(1.0, 'J', fuel.units)
        fuel.timeseries = values.map { |v| v * unit_conv }
      end
    end

    fuels.values.each do |fuel|
      fuel.timeseries = [0] * fuels[[FT::Elec, false]].timeseries.size if fuel.timeseries.empty?
    end

    # Convert hourly data to monthly data
    num_days_in_month = Constants.NumDaysInMonths(2002) # Arbitrary non-leap year
    fuels.each do |(fuel_type, _is_production), fuel|
      next unless fuel_type != FT::Elec || utility_bill_scenario.elec_tariff_filepath.nil?

      ts_data = fuel.timeseries.dup
      fuel.timeseries = []
      start_day = 0
      num_days_in_month.each do |num_days|
        fuel.timeseries << ts_data[start_day * 24..(start_day + num_days) * 24 - 1].sum
        start_day += num_days
      end
    end

    return fuels
  end

  def _bill_calcs(fuels, utility_rates, utility_bills, header, pv_systems, utility_bill_scenario)
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
    output_format = 'csv'
    output_path = File.join(File.dirname(__FILE__), "results_bills.#{output_format}")

    @measure.get_utility_rates(@hpxml_path, fuels, utility_rates, utility_bill_scenario, pv_systems)
    @measure.get_utility_bills(fuels, utility_rates, utility_bills, utility_bill_scenario, header)
    @measure.get_annual_bills(utility_bills)

    @measure.write_runperiod_output_results(runner, utility_bills, output_format, output_path, utility_bill_scenario.name)
  end

  def _test_measure(expected_errors: [], expected_warnings: [])
    # Run measure via OSW
    require 'json'
    template_osw = File.join(File.dirname(__FILE__), '..', '..', 'workflow', 'template-run-hpxml.osw')
    workflow = OpenStudio::WorkflowJSON.new(template_osw)
    json = JSON.parse(workflow.to_s)

    # Update measure args
    steps = OpenStudio::WorkflowStepVector.new
    found_args = []
    json['steps'].each do |json_step|
      step = OpenStudio::MeasureStep.new(json_step['measure_dir_name'])
      json_step['arguments'].each do |json_arg_name, json_arg_val|
        if @args_hash.keys.include? json_arg_name
          # Override value
          found_args << json_arg_name
          json_arg_val = @args_hash[json_arg_name]
        end
        step.setArgument(json_arg_name, json_arg_val)
      end
      steps.push(step)
    end
    workflow.setWorkflowSteps(steps)
    osw_path = File.join(File.dirname(template_osw), 'test.osw')
    workflow.saveAs(osw_path)
    assert_equal(@args_hash.size, found_args.size)

    # Run OSW
    command = "#{OpenStudio.getOpenStudioCLI} run -w #{osw_path}"
    cli_output = `#{command}`

    # Cleanup
    File.delete(osw_path)

    bills_csv = File.join(File.dirname(template_osw), 'run', 'results_bills.csv')

    # check warnings/errors
    if not expected_errors.empty?
      expected_errors.each do |expected_error|
        assert(cli_output.include?("ERROR] #{expected_error}"))
      end
    end
    if not expected_warnings.empty?
      expected_warnings.each do |expected_warning|
        assert(cli_output.include?("WARN] #{expected_warning}"))
      end
    end

    return bills_csv
  end
end
