require 'test_helper'
require 'json'

class JSONSchemer::TestableFormat
  extend JSONSchemer::Format
end

class JSONSchemer::FormatTest < Minitest::Test
  def test_format_does_not_blow_up_on_invalid_data
    [[], {}, nil, 123].each do |invalid|
      refute JSONSchemer::TestableFormat.valid_format?(invalid, 'email')
    end
  end
end
