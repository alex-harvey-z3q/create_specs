require 'spec_helper'
require_relative '../create_specs'
require 'digest'

describe SpecWriter do
  before(:all) do
    @output_file = 'ntp_spec.rb'
    @options = {
      :excludes => ['Stage', 'Class', 'Anchor', 'Notify', 'Node', '/::/'],
      :only_include => [],
    }
  end

  before(:each) do
    # "use of doubles from rspec-mocks outside of the per-test lifecycle is
    # not supported" - thus before each.
    #
    allow($stdout).to receive(:puts)
  end

  context 'default options' do
    it 'should not raise errors' do
      @spec_writer = SpecWriter.new(
        'spec/fixtures/ntp.json', @output_file, @options
      )
      expect { @spec_writer.write }.to_not raise_error
    end

    it 'should generate output file with expected md5sum' do
      md5 = Digest::MD5.hexdigest(File.open(@output_file).read)
      expect(md5).to eq "e5f0e3238e223d459d016a363847421d"
    end
  end

  context 'include defined types' do
    before(:all) do
      @options[:excludes].pop
    end

    it 'should not raise errors' do
      @spec_writer = SpecWriter.new(
        'spec/fixtures/ntp.json', @output_file, @options
      )
      expect { @spec_writer.write }.to_not raise_error
    end

    it 'should generate output file with expected md5sum' do
      md5 = Digest::MD5.hexdigest(File.open(@output_file).read)
      expect(md5).to eq "362ae493fb4ff352065360ac60f85704"
    end
  end

  context 'a v3 version of the catalog' do
    it 'should generate output file with expected md5sum' do
      @spec_writer = SpecWriter.new(
        'spec/fixtures/ntp_v3.json', @output_file, @options
      )
      @spec_writer.write
      md5 = Digest::MD5.hexdigest(File.open(@output_file).read)
      expect(md5).to eq "e5f0e3238e223d459d016a363847421d"
    end
  end

  context 'set a different output file' do
    before(:all) do
      @new_output_file = 'new_output_file.rb'
    end

    it 'should write to a new locations' do
      @spec_writer = SpecWriter.new(
        'spec/fixtures/ntp.json', @new_output_file, @options
      )
      @spec_writer.write
      expect(File.exists?(@new_output_file)).to be true
    end

    after(:all) do
      FileUtils.rm(@new_output_file)
    end
  end

  context 'include-only option' do
    before(:all) do
      @options[:only_include] = ['Service[ntp]']
    end

    it 'should generate output file with expected md5sum' do
      @spec_writer = SpecWriter.new(
        'spec/fixtures/ntp.json', @output_file, @options
      )
      @spec_writer.write
      md5 = Digest::MD5.hexdigest(File.open(@output_file).read)
      expect(md5).to eq "5a7e67ac7fc8ad94e27760fc7c39346b"
    end
  end

  after(:all) do
    FileUtils.rm(@output_file)
  end
end