Feature: Start up Emissary
  In order to get emissary configured to run properly
  As an instance owner
  I want to pass a configuration file to the program

  Scenario: No configuration file
    Given I have not created a configuration file
    When Emissary starts
    Then it should raise an Emissary::ConfigValidationError error containing message '[general][operators] not set'

  Scenario: Poorly configured file
    Given I have created a configuration file
    And it is not a well formed configuration file
    When Emissary starts
    Then it should raise an Emissary::ConfigValidationError error containing message '[general][operators] not set'

    #  Scenario: Well configured file
    #    Given I have created a configuration file
    #    And it is a well formed configuration file
    #    When Emissary starts
    #    Then it should not raise an error
    #    And it should daemonize
