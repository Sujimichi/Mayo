require 'spec_helper'
require 'fileutils'


describe CukeResultReader do
  describe "general_function" do 
    before(:each) do 
      @results = sample_results_1
      @reader = CukeResultReader.new(@results)
    end

    it 'should take an array of results' do 
      @reader.results.should == @results
    end

    describe "process results" do 
      before(:each) do 
        @reader.process_results
      end

      it 'should collect failing steps from each result together' do 
        @reader.failed_steps.size.should == 2 #there are 2 failed steps in sample_results_1
        @reader.failed_steps[0].should == ["", "\e[31mexpected false to be true (RSpec::Expectations::ExpectationNotMetError)\e[0m", "\e[31m./features/step_definitions/jvr_report_steps.rb:147:in `/^I should see (\\d+) reports with (\\d+) updating$/'\e[0m", "\e[31mfeatures/07_reports_panel/deleting_reports.feature:13:in `Then I should see 1 reports with 1 updating'\e[0m"]
        @reader.failed_steps[1].should == ["","\e[31mUser got bored of waiting (RuntimeError)\e[0m", "\e[31m./features/step_definitions/jvr_report_steps.rb:14:in `/^I wait for the report processing to complete$/'\e[0m", "\e[31mfeatures/07_reports_panel/create_reports.feature:14:in `And I wait for the report processing to complete'\e[0m"]

      end

      it 'should collect the failing scenarios from each result' do 
        @reader.failing_scenarios.size.should == 2
        @reader.failing_scenarios.should == ["\e[31mcucumber -p all features/07_reports_panel/deleting_reports.feature:5\e[0m\e[90m # Scenario: Deleteing All Reports deletes all reports and re creates a new AllProbs report\e[0m", "\e[31mcucumber -p all features/07_reports_panel/create_reports.feature:11\e[0m\e[90m # Scenario: When a report has processed it should be shown to be ready\e[0m"]

      end

      it 'should be able to present the failing scenarios as a command' do 
        @reader.failing_scenario_command.should == ["bundle exec cucumber -p all features/support features/step_definitions", "features/07_reports_panel/deleting_reports.feature:5 features/07_reports_panel/create_reports.feature:11"]
      end

      it 'should collect the summary info from each result' do 
        @reader.summaries.size.should == 3
        @reader.summaries.should== [
          ["7 scenarios (\e[31m1 failed\e[0m, \e[32m6 passed\e[0m)", "40 steps (\e[31m1 failed\e[0m, \e[32m39 passed\e[0m)", "1m30.124s"],
          ["7 scenarios (\e[31m1 failed\e[0m, \e[32m6 passed\e[0m)", "43 steps (\e[31m1 failed\e[0m, \e[36m1 skipped\e[0m, \e[32m41 passed\e[0m)", "2m21.135s"],
          ["7 scenarios (\e[32m7 passed\e[0m)", "50 steps (\e[32m50 passed\e[0m)", "2m36.798s"]
        ]

      end

      it 'should sum the summaries values' do 
        @reader.summary.should == [
          "21 scenarios (\e[31m2 failed\e[0m, \e[32m19 passed\e[0m)", 
          "133 steps (\e[31m2 failed\e[0m, \e[36m1 skipped\e[0m, \e[32m130 passed\e[0m)", 
          "6m28.057s"
        ]

      end

      it 'should collect the progress markers' do 
        @reader.progress_markers.should == ["\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[31mF\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m", "\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[31mF\e[0m\e[36m-\e[0m", "^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m"]
      end
    end
  end
  describe "general_function with all passing tests with single scenario results" do 
    before(:each) do 
      @results = sample_results_2
      @reader = CukeResultReader.new(@results)
      @reader.process_results
    end

    it 'should show correct summary values' do 
      @reader.summary.should == [
        "3 scenarios (\e[32m3 passed\e[0m)", 
        "19 steps (\e[32m19 passed\e[0m)", 
        "1m16.208s"
      ]     
    end

    it 'should have empty? failing_scenarios and failed_steps' do 
      @reader.failing_scenarios.should be_empty
      @reader.failed_steps.should be_empty
    end


  end
end

def sample_results_1
  [["Result from testslave1-VB", "Using the all profile...", "Starting The Fantastic Cucumber", "\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[31mF\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m", "", "\e[31m(::) failed steps (::)\e[0m", "", "\e[31mexpected false to be true (RSpec::Expectations::ExpectationNotMetError)\e[0m", "\e[31m./features/step_definitions/jvr_report_steps.rb:147:in `/^I should see (\\d+) reports with (\\d+) updating$/'\e[0m", "\e[31mfeatures/07_reports_panel/deleting_reports.feature:13:in `Then I should see 1 reports with 1 updating'\e[0m", "", "\e[31mFailing Scenarios:\e[0m", "\e[31mcucumber -p all features/07_reports_panel/deleting_reports.feature:5\e[0m\e[90m # Scenario: Deleteing All Reports deletes all reports and re creates a new AllProbs report\e[0m", "", "7 scenarios (\e[31m1 failed\e[0m, \e[32m6 passed\e[0m)", "40 steps (\e[31m1 failed\e[0m, \e[32m39 passed\e[0m)", "1m30.124s", "vWorkers down"], ["Result from testslave2-VB", "Using the all profile...", "Starting The Fantastic Cucumber", "\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[31mF\e[0m\e[36m-\e[0m", "", "\e[31m(::) failed steps (::)\e[0m", "", "\e[31mUser got bored of waiting (RuntimeError)\e[0m", "\e[31m./features/step_definitions/jvr_report_steps.rb:14:in `/^I wait for the report processing to complete$/'\e[0m", "\e[31mfeatures/07_reports_panel/create_reports.feature:14:in `And I wait for the report processing to complete'\e[0m", "", "\e[31mFailing Scenarios:\e[0m", "\e[31mcucumber -p all features/07_reports_panel/create_reports.feature:11\e[0m\e[90m # Scenario: When a report has processed it should be shown to be ready\e[0m", "", "7 scenarios (\e[31m1 failed\e[0m, \e[32m6 passed\e[0m)", "43 steps (\e[31m1 failed\e[0m, \e[36m1 skipped\e[0m, \e[32m41 passed\e[0m)", "2m21.135s", "vWorkers down"], ["Result from yokai", "Using the all profile...", "Starting The Fantastic Cucumber", "^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0mv^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m", "", "7 scenarios (\e[32m7 passed\e[0m)", "50 steps (\e[32m50 passed\e[0m)", "2m36.798s", "vWorkers down"]]

end

def sample_results_2
  [["Result from yokai", "Using the all profile...", "Starting The Fantastic Cucumber", "^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m", "", "1 scenario (\e[32m1 passed\e[0m)", "5 steps (\e[32m5 passed\e[0m)", "0m24.604s", "vWorkers down"], ["Result from testslave2-VB", "Using the all profile...", "Starting The Fantastic Cucumber", "^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m", "", "1 scenario (\e[32m1 passed\e[0m)", "6 steps (\e[32m6 passed\e[0m)", "0m23.059s", "vWorkers down"], ["Result from testslave1-VB", "Using the all profile...", "Starting The Fantastic Cucumber", "^\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m\e[32m.\e[0m", "", "1 scenario (\e[32m1 passed\e[0m)", "8 steps (\e[32m8 passed\e[0m)", "0m28.545s", "vWorkers down"]]
end
