# frozen_string_literal: true

require "rails_helper"

RSpec.describe Project, "DXF validation", type: :model do
  let(:project) { Project.create!(title: "Validation test", ephemeral: true) }

  def with_temp_file(filename, content)
    tempfile = Tempfile.new([File.basename(filename, ".*"), File.extname(filename)])
    File.binwrite(tempfile.path, content)
    tempfile.rewind
    yield tempfile
  ensure
    tempfile.close
    tempfile.unlink
  end

  it "accepts a standard valid DXF file" do
    valid_content = "  0\nSECTION\n  2\nHEADER\n  0\nENDSEC"
    with_temp_file("valid.dxf", valid_content) do |tempfile|
      project.input_dxf.attach(
        io: tempfile,
        filename: "valid.dxf",
        content_type: "application/dxf"
      )
      expect(project).to be_valid
    end
  end

  it "rejects files larger than 10 MB" do
    large_content = "SECTION\n" + ("X" * (10.megabytes + 1))
    with_temp_file("too_large.dxf", large_content) do |tempfile|
      project.input_dxf.attach(
        io: tempfile,
        filename: "too_large.dxf",
        content_type: "application/dxf"
      )
      expect(project).not_to be_valid
      expect(project.errors.added?(:input_dxf, :too_large)).to be(true)
    end
  end

  it "rejects files with non-dxf extension" do
    valid_content_bad_ext = "  0\nSECTION\n  2\nHEADER\n  0\nENDSEC"
    with_temp_file("valid.txt", valid_content_bad_ext) do |tempfile|
      project.input_dxf.attach(
        io: tempfile,
        filename: "valid.txt",
        content_type: "text/plain"
      )
      expect(project).not_to be_valid
      expect(project.errors.added?(:input_dxf, :invalid_extension)).to be(true)
    end
  end

  it "rejects files without SECTION marker" do
    invalid_content = "  0\nINVALID\n  0\nENDSEC"
    with_temp_file("corrupt.dxf", invalid_content) do |tempfile|
      project.input_dxf.attach(
        io: tempfile,
        filename: "corrupt.dxf",
        content_type: "application/dxf"
      )
      expect(project).not_to be_valid
      expect(project.errors.added?(:input_dxf, :corrupt_dxf)).to be(true)
    end
  end

  describe "persisted files validation" do
    it "rejects persisted files that are too large, have bad extension, or are corrupt" do
      # Attach invalid files by saving without validation within nested blocks to keep them alive
      large_content = "SECTION\n" + ("X" * (10.megabytes + 1))
      with_temp_file("too_large.dxf", large_content) do |temp_large|
        with_temp_file("valid.txt", "  0\nSECTION\n  0\nENDSEC") do |temp_txt|
          with_temp_file("corrupt.dxf", "  0\nINVALID\n  0\nENDSEC") do |temp_corrupt|
            project.input_dxf.attach([
              { io: temp_large, filename: "too_large.dxf", content_type: "application/dxf" },
              { io: temp_txt, filename: "valid.txt", content_type: "text/plain" },
              { io: temp_corrupt, filename: "corrupt.dxf", content_type: "application/dxf" }
            ])
            project.save!(validate: false)
          end
        end
      end

      # Reload and validate
      project.reload
      expect(project).not_to be_valid
      expect(project.errors.added?(:input_dxf, :too_large)).to be(true)
      expect(project.errors.added?(:input_dxf, :invalid_extension)).to be(true)
      expect(project.errors.added?(:input_dxf, :corrupt_dxf)).to be(true)
    end

    it "handles missing files from active storage service gracefully" do
      valid_content = "  0\nSECTION\n  2\nHEADER\n  0\nENDSEC"
      with_temp_file("valid.dxf", valid_content) do |tempfile|
        project.input_dxf.attach(io: tempfile, filename: "valid.dxf", content_type: "application/dxf")
        project.save!
      end
      
      project.reload
      allow_any_instance_of(ActiveStorage::Blob).to receive(:open).and_raise(ActiveStorage::FileNotFoundError)
      expect(project).not_to be_valid
      expect(project.errors.added?(:input_dxf, :corrupt_dxf)).to be(true)
    end

    it "covers fallback and error branches in validate_input_dxf_files" do
      puts "DEBUG: project.input_dxf = #{project.input_dxf.inspect}"
      # 1. Attachable does not match Hash, tempfile, or download
      dummy_attachable = Object.new
      changes_mock = double(attachables: [dummy_attachable], attachments: [])
      allow(project).to receive(:attachment_changes).and_return({ "input_dxf" => changes_mock })
      expect(project).to be_valid

      # 2. FileNotFoundError rescue on attachable.download
      blob_mock = double(download: nil)
      allow(blob_mock).to receive(:respond_to?).with(:tempfile).and_return(false)
      allow(blob_mock).to receive(:respond_to?).with(:download).and_return(true)
      allow(blob_mock).to receive(:download).and_raise(ActiveStorage::FileNotFoundError)
      allow(blob_mock).to receive(:filename).and_return("missing.dxf")
      
      changes_mock2 = double(attachables: [blob_mock], attachments: [])
      allow(project).to receive(:attachment_changes).and_return({ "input_dxf" => changes_mock2 })
      expect(project).not_to be_valid

      # 3. Attachable is Hash with io responding to length but not size
      io_length_only = double
      allow(io_length_only).to receive(:length).and_return(100)
      allow(io_length_only).to receive(:read).and_return("SECTION")

      changes_mock3 = double(attachables: [{ io: io_length_only, filename: "length_only.dxf" }], attachments: [])
      allow(project).to receive(:attachment_changes).and_return({ "input_dxf" => changes_mock3 })
      expect(project).to be_valid

      # 4. Attachable is Hash with io responding to neither size nor length
      io_neither = double
      allow(io_neither).to receive(:read).and_return("SECTION")

      changes_mock4 = double(attachables: [{ io: io_neither, filename: "neither.dxf" }], attachments: [])
      allow(project).to receive(:attachment_changes).and_return({ "input_dxf" => changes_mock4 })
      expect(project).to be_valid

      # 5. Attachment has a nil blob
      changes_mock5 = double(attachables: [], attachments: [])
      allow(project).to receive(:attachment_changes).and_return({ "input_dxf" => changes_mock5 })
      attachment_with_nil_blob = double(blob: nil)
      allow(project.input_dxf).to receive(:attachments).and_return([attachment_with_nil_blob])
      expect(project).to be_valid
    end
  end
end
