require 'rails_helper'
require 'huginn_agent/spec_helper'

describe Agents::EtherscanAgent do
  before(:each) do
    @valid_options = Agents::EtherscanAgent.new.default_options
    @checker = Agents::EtherscanAgent.new(:name => "EtherscanAgent", :options => @valid_options)
    @checker.user = users(:bob)
    @checker.save!
  end

  pending "add specs here"
end
