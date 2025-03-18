require "spec"
require "hrx"
require "semantic_version"

lib LibXML
  $xmlParserVersion : LibC::Char*
end

private def libxml_version
  number = String.new(LibXML.xmlParserVersion).to_i
  "#{number // 10_000}.#{number % 10_000 // 100}.#{number % 100}"
end

def run_hrx_samples_dir(dir)
  Dir.each_child(dir) do |child|
    path = dir.join(child)
    if path.extension == ".hrx"
      describe path.basename do
        run_hrx_samples(path)
      end
    end
  end
end

def run_hrx_samples(archive_file, policies, *, relative_to = __DIR__)
  File.open(Path[archive_file].expand(relative_to), "r") do |io|
    describe archive_file.to_s do
      source = nil
      source_was_used = true
      HRX.parse(io) do |file|
        if file.path.starts_with?("pending:")
          name = File.dirname(file.path).lchop("pending:")
          pending(name) { }
          next
        end

        extension = File.extname(file.path)
        basename = File.basename(file.path, extension)
        case basename
        when "document", "fragment"
          if source && !source_was_used
            it_hrx_sample(policies, source, archive_file.to_s)
          end
          source = file
          source_was_used = false
        else
          next unless source
          source_was_used = true

          it_hrx_sample(policies, source, file, archive_file.to_s)
        end
      end
    end
  end
end

private LIBXML2_VERSION = SemanticVersion.parse(libxml_version)

def test_libxml_version(path)
  md = path.match(/^libxml2(<|<=|==|>=|>)([^:]+)/) || return path

  comparator = md[1]
  version = SemanticVersion.parse(md[2])

  case comparator
  when "<"
    return unless LIBXML2_VERSION < version
  when "<="
    return unless LIBXML2_VERSION <= version
  when "=="
    return unless LIBXML2_VERSION == version
  when ">="
    return unless LIBXML2_VERSION >= version
  when ">"
    return unless LIBXML2_VERSION > version
  else
    fail "Unrecgonized libxml2 version constraint: #{comparator.inspect} in #{path}"
  end

  path.byte_slice((md.byte_end + 1)..)
end

def it_hrx_sample(policies, source, expected, archive_file)
  extension = File.extname(expected.path)
  path = test_libxml_version(expected.path) || return
  basename = File.basename(path, extension)

  found_policy = true
  policy = policies.fetch(basename) { found_policy = false; nil }
  if !policy && found_policy
    pending "#{File.dirname(source.path)} #{expected.path}"
    return
  end

  it "#{File.dirname(source.path)} (#{expected.path})" do
    if p = policy
      assert_sanitize(p, source, expected, file: archive_file)
    else
      fail "Unregistered policy #{basename}"
    end
  end
end

def it_hrx_sample(policies, source, archive_file)
  describe File.dirname(source.path) do
    policies.each do |name, policy|
      next unless policy
      it name do
        assert_sanitize(policy, source, source, file: archive_file)
      end
    end
  end
end

def assert_sanitize(policy, source, expected, *, file = __FILE__)
  if File.basename(source.path, File.extname(source.path)) == "fragment"
    policy.process(source.content).should eq(expected.content), file: file, line: expected.line
  else
    policy.process_document(source.content).should eq(expected.content), file: file, line: expected.line
  end
end
