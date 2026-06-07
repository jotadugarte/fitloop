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

  describe ".from_project" do
    it "builds instance from project curve_tolerance_mm" do
      project = instance_double(Project, curve_tolerance_mm: 0.25)
      expect(described_class.from_project(project).to_f).to eq(0.25)
    end
  end

  describe "equality and hashing" do
    it "compares properly and generates consistent hash" do
      v1 = described_class.parse(0.1)
      v2 = described_class.parse(0.1)
      v3 = described_class.parse(0.2)
      expect(v1).to eq(v2)
      expect(v1.eql?(v2)).to be(true)
      expect(v1).not_to eq(v3)
      expect(v1).not_to eq(nil)
      expect(v1).not_to eq("another_type")
      expect(v1.hash).to eq(v2.hash)
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

  describe ".from_project" do
    it "builds instance from project sheet_gap_mm" do
      project = instance_double(Project, sheet_gap_mm: 20)
      expect(described_class.from_project(project).to_f).to eq(20.0)
    end
  end

  describe "equality and hashing" do
    it "compares properly and generates consistent hash" do
      v1 = described_class.parse(15)
      v2 = described_class.parse(15)
      v3 = described_class.parse(20)
      expect(v1).to eq(v2)
      expect(v1.eql?(v2)).to be(true)
      expect(v1).not_to eq(v3)
      expect(v1).not_to eq(nil)
      expect(v1).not_to eq("another_type")
      expect(v1.hash).to eq(v2.hash)
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

  describe ".from_project" do
    it "builds instance from project nesting_time_limit_sec" do
      project = instance_double(Project, nesting_time_limit_sec: 300)
      expect(described_class.from_project(project).to_i).to eq(300)
    end
  end

  describe "equality and hashing" do
    it "compares properly and generates consistent hash" do
      v1 = described_class.parse(600)
      v2 = described_class.parse(600)
      v3 = described_class.parse(300)
      expect(v1).to eq(v2)
      expect(v1.eql?(v2)).to be(true)
      expect(v1).not_to eq(v3)
      expect(v1).not_to eq(nil)
      expect(v1).not_to eq("another_type")
      expect(v1.hash).to eq(v2.hash)
    end
  end
end

RSpec.describe Nesting::KerfMm, "[REQ-FIT-NEST-002]" do
  describe ".parse" do
    it "accepts non-negative float" do
      expect(described_class.parse(2.5).to_f).to eq(2.5)
    end

    it "rejects negative and nil" do
      expect { described_class.parse(-0.5) }.to raise_error(ArgumentError)
      expect { described_class.parse(nil) }.to raise_error(ArgumentError)
    end
  end

  describe ".from_project" do
    it "builds instance from project kerf_mm" do
      project = instance_double(Project, kerf_mm: 3.2)
      expect(described_class.from_project(project).to_f).to eq(3.2)
    end
  end

  describe "equality and hashing" do
    it "compares properly and generates consistent hash" do
      v1 = described_class.parse(2.5)
      v2 = described_class.parse(2.5)
      v3 = described_class.parse(3.0)
      expect(v1).to eq(v2)
      expect(v1.eql?(v2)).to be(true)
      expect(v1).not_to eq(v3)
      expect(v1).not_to eq(nil)
      expect(v1).not_to eq("another_type")
      expect(v1.hash).to eq(v2.hash)
    end
  end
end

RSpec.describe Nesting::MarginMm, "[REQ-FIT-NEST-002]" do
  describe ".parse" do
    it "accepts non-negative float" do
      expect(described_class.parse(5.0).to_f).to eq(5.0)
    end

    it "rejects negative and nil" do
      expect { described_class.parse(-1.0) }.to raise_error(ArgumentError)
      expect { described_class.parse(nil) }.to raise_error(ArgumentError)
    end
  end

  describe ".from_project" do
    it "builds instance from project margin_mm" do
      project = instance_double(Project, margin_mm: 10.0)
      expect(Nesting::MarginMm.from_project(project).to_f).to eq(10.0)
    end
  end

  describe "equality and hashing" do
    it "compares properly and generates consistent hash" do
      v1 = Nesting::MarginMm.parse(5.0)
      v2 = Nesting::MarginMm.parse(5.0)
      v3 = Nesting::MarginMm.parse(10.0)
      expect(v1).to eq(v2)
      expect(v1.eql?(v2)).to be(true)
      expect(v1).not_to eq(v3)
      expect(v1).not_to eq(nil)
      expect(v1).not_to eq("another_type")
      expect(v1.hash).to eq(v2.hash)
    end
  end
end
