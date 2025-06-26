# Ensure test support modules are compiled
Code.require_file("support/test_integration.ex", __DIR__)

ExUnit.start()
