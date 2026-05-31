# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::CurveToleranceMm, "[REQ-FIT-DOM-001]" do
  describe ".parse" do
    it "accepts positive values" do
      expect(described_class.parse(0.1).to_f).to eq(0.1)
    end

    it "rejects zero, negative, and nil" do
      expect { described_class.parse(0) }.to raise_error(ArgumentError, /positive/)
      expect { described_class.parse(-0.1) }.to raise_error(ArgumentError, /positive/)
      expect { described_class.parse(nil) }.to raise_error(ArgumentError, /required/)
    end
  end
end

RSpec.describe Nesting::SheetGapMm, "[REQ-FIT-NEST-002]" do
  describe ".parse" do
    it "accepts zero and positive values" do
      expect(described_class.parse(15).to_f).to eq(15.0)
    end

    it "rejects negative and nil" do
      expect { described_class.parse(-1) }.to raise_error(ArgumentError, /non-negative/)
      expect { described_class.parse(nil) }.to raise_error(ArgumentError, /required/)
    end
  end
end

RSpec.describe Nesting::NestingTimeLimitSec, "[REQ-FIT-JOB-001]" do
  describe ".parse" do
    it "accepts positive integers" do
      expect(described_class.parse(600).to_i).to eq(600)
    end

    it "rejects zero, negative, and nil" do
      expect { described_class.parse(0) }.to raise_error(ArgumentError, /positive/)
      expect { described_class.parse(-1) }.to raise_error(ArgumentError, /positive/)
      expect { described_class.parse(nil) }.to raise_error(ArgumentError, /required/)
    end
  end
end
