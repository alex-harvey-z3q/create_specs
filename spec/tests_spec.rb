require 'spec_helper'
require_relative '../create_specs'
require 'digest'

describe SpecWriter do
  before(:all) do
    @options = {
      :excludes => ['Stage', 'Class', 'Anchor', 'Notify', 'Node', '/::/'],
      :only_include => [],
      :md5sums => false,
      :class_name => nil,
      :setup => {},
      :output_file => 'out_spec.rb',
      :compile_test => true,
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
      @options[:catalog_file] = 'spec/fixtures/ntp.json'
      @spec_writer = SpecWriter.new(@options)
      expect { @spec_writer.write }.to_not raise_error
    end

    it 'should generate output file with expected md5sum' do
      md5 = Digest::MD5.hexdigest(File.open(@options[:output_file]).read)
      expect(md5).to eq "e5f0e3238e223d459d016a363847421d"
    end
  end

  context 'no notify' do
    it 'should not raise errors' do
      @options[:catalog_file] = 'spec/fixtures/notify.json'
      @options[:excludes].delete('Notify')
      @spec_writer = SpecWriter.new(@options)
      expect { @spec_writer.write }.to_not raise_error
    end

    it 'should generate output file with expected md5sum' do
      md5 = Digest::MD5.hexdigest(File.open(@options[:output_file]).read)
      expect(md5).to eq "64729b78b911f838403783e98ce536df"
    end
  end

  context 'include defined types' do
    before(:all) do
      @options[:catalog_file] = 'spec/fixtures/ntp.json'
      @options[:excludes] = ['Stage', 'Class', 'Anchor', 'Notify', 'Node']
    end

    it 'should not raise errors' do
      @spec_writer = SpecWriter.new(@options)
      expect { @spec_writer.write }.to_not raise_error
    end

    it 'should generate output file with expected md5sum' do
      md5 = Digest::MD5.hexdigest(File.open(@options[:output_file]).read)
      expect(md5).to eq "362ae493fb4ff352065360ac60f85704"
    end
  end

  context 'a v3 version of the catalog' do
    it 'should generate output file with expected md5sum' do
      @options[:catalog_file] = 'spec/fixtures/ntp_v3.json'
      @spec_writer = SpecWriter.new(@options)
      @spec_writer.write
      md5 = Digest::MD5.hexdigest(File.open(@options[:output_file]).read)
      expect(md5).to eq "e5f0e3238e223d459d016a363847421d"
    end
  end

  context 'set a different output file' do
    before(:all) do
      @options[:output_file] = 'new_output_file.rb'
      @options[:catalog_file] = 'spec/fixtures/ntp.json'
    end

    it 'should write to a new locations' do
      @spec_writer = SpecWriter.new(@options)
      @spec_writer.write
      expect(File.exists?(@options[:output_file])).to be true
      FileUtils.rm(@options[:output_file])
    end
  end

  context 'md5sum option' do
    before(:all) do
      @options[:md5sums] = true
      @options[:output_file] = 'out_spec.rb'
    end

    it 'should generate output file with expected md5sum' do
      @spec_writer = SpecWriter.new(@options)
      @spec_writer.write
      md5 = Digest::MD5.hexdigest(File.open(@options[:output_file]).read)
      expect(md5).to eq "4a25c4880a7f2022767af1394a9417b9"
    end
  end

  context 'include-only option' do
    before(:all) do
      @options[:md5sums] = false
    end

    it 'only include Service[ntp]' do
      @options[:only_include] = ['Service[ntp]']
      @spec_writer = SpecWriter.new(@options)
      @spec_writer.write
      md5 = Digest::MD5.hexdigest(File.open(@options[:output_file]).read)
      expect(md5).to eq "b11147a8f515c49ead968bf9e37db206"
    end

    it 'only include File[/.*/]' do
      @options[:only_include] = ['File[/.*/]']
      @spec_writer = SpecWriter.new(@options)
      @spec_writer.write
      md5 = Digest::MD5.hexdigest(File.open(@options[:output_file]).read)
      expect(md5).to eq "28a997b02c5f5322a28e9849fe5b1046"
    end

    it 'only include File[/ntp.conf/]' do
      @options[:only_include] = ['File[/ntp.conf/]']
      @spec_writer = SpecWriter.new(@options)
      @spec_writer.write
      md5 = Digest::MD5.hexdigest(File.open(@options[:output_file]).read)
      expect(md5).to eq "28a997b02c5f5322a28e9849fe5b1046"
    end

    it 'only include File[/\/etc\/ntp\.conf/]' do
      @options[:only_include] = ['File[/\/etc\/ntp\.conf/]']
      @spec_writer = SpecWriter.new(@options)
      @spec_writer.write
      md5 = Digest::MD5.hexdigest(File.open(@options[:output_file]).read)
      expect(md5).to eq "28a997b02c5f5322a28e9849fe5b1046"
    end

    it 'only include /File/' do
      @options[:only_include] = ['/File/']
      @spec_writer = SpecWriter.new(@options)
      @spec_writer.write
      md5 = Digest::MD5.hexdigest(File.open(@options[:output_file]).read)
      expect(md5).to eq "28a997b02c5f5322a28e9849fe5b1046"
    end

    it 'only include File[/xyz/]' do
      @options[:only_include] = ['File[/xyz/]']
      @spec_writer = SpecWriter.new(@options)
      @spec_writer.write
      md5 = Digest::MD5.hexdigest(File.open(@options[:output_file]).read)
      expect(md5).to eq "ac718c6d0eaf05883e36750b83ebe007" # a file with params and compile only.
    end

    it 'only include an invalid regexp File[/xyz(/]' do
      @options[:only_include] = ['File[/xyz(/]']
      @spec_writer = SpecWriter.new(@options)
      expect { @spec_writer.write }.to raise_error(RuntimeError)
    end
  end

  context 'user-specified class_name' do
    before(:all) do
      @options[:only_include] = []
    end

    it 'should use a user-specified class name' do
      @options[:class_name] = 'default'
      @spec_writer = SpecWriter.new(@options)
      @spec_writer.write
      md5 = Digest::MD5.hexdigest(File.open(@options[:output_file]).read)
      expect(md5).to eq "0a03d975ae5b8f54e0baeda176a466d3"
    end
  end

  context 'custom setup' do
    before(:all) do
      @options[:setup] = {
        :pre_condition => ["hiera_include('classes')"],
        :hiera_config  => 'spec/fixtures/hiera.yaml',
        :facts         => {
          'foo' => 'bar',
          'baz' => 'qux',
        },
      }
    end

    it 'should intepolate custom setup code' do
      @spec_writer = SpecWriter.new(@options)
      @spec_writer.write
      md5 = Digest::MD5.hexdigest(File.open(@options[:output_file]).read)
      expect(md5).to eq "d645bd611fdddcb907755879c09efce7"
    end
  end

  after(:all) do
    FileUtils.rm(@options[:output_file])
  end
end
