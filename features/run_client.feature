Feature: Run Emissary using EmissaryClient tool
  In order to run Emissary in an easy and configurable way from the commandline
  As a systems operator
  I want to run the `emissary' command and have the application run properly

  Scenario: Start the process
    Given the process is not running
    When I call './bin/emissary -h'
    Then the help page should be displayed

  Scenario: Start 
