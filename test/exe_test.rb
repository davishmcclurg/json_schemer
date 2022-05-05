require 'test_helper'
require 'open3'

class ExeTest < Minitest::Test
  GEM_PATH = File.join(__dir__, '..', 'tmp', 'gems')
  CMD = File.join(GEM_PATH, 'bin', 'json_schemer')
  SCHEMA1 = File.join(__dir__, 'schemas', 'schema1.json')
  VALID = { 'id' => 1, 'a' => 'valid' }
  INVALID1 = { 'a' => 'invalid' }
  INVALID2 = { 'id' => 1 }
  INVALID3 = { 'id' => 1, 'a' => -1 }
  INVALID4 = { 'id' => 'invalid', 'a' => 'valid' }
  INVALID5 = { 'x' => 'invalid' }

  def test_help
    stdout, stderr, status = exe('-h')
    assert_predicate(status, :success?)
    assert_empty(stderr)
    assert_includes(stdout, 'json_schemer [options]')
    assert_includes(stdout, '-e, --errors MAX')
    assert_includes(stdout, '-h, --help')
    assert_includes(stdout, '-v, --version')
  end

  def test_version
    stdout, stderr, status = exe('--version')
    assert_predicate(status, :success?)
    assert_empty(stderr)
    assert_includes(stdout, JSONSchemer::VERSION)
  end

  def test_errors
    stdout, stderr, status = exe
    refute_predicate(status, :success?)
    assert_includes(stderr, 'json_schemer: no schema or data')
    assert_empty(stdout)

    stdout, stderr, status = exe(SCHEMA1)
    refute_predicate(status, :success?)
    assert_includes(stderr, 'json_schemer: no data')
    assert_empty(stdout)

    stdout, stderr, status = exe('-', SCHEMA1, '-')
    refute_predicate(status, :success?)
    assert_includes(stderr, 'json_schemer: multiple stdin')
    assert_empty(stdout)
  end

  def test_success
    tmp_json(VALID) do |path|
      stdout, stderr, status = exe(SCHEMA1, path)
      assert_predicate(status, :success?)
      assert_empty(stderr)
      assert_empty(stdout)

      stdout, stderr, status = exe('--errors', '0', SCHEMA1, path)
      assert_predicate(status, :success?)
      assert_empty(stderr)
      assert_empty(stdout)

      stdout, stderr, status = exe('--errors', '1', SCHEMA1, path)
      assert_predicate(status, :success?)
      assert_empty(stderr)
      assert_empty(stdout)
    end
  end

  def test_error_output
    stdout, stderr, status = tmp_json(VALID, INVALID1, INVALID2, INVALID3, INVALID4, INVALID5) do |*paths|
      exe(SCHEMA1, *paths)
    end
    refute_predicate(status, :success?)
    assert_empty(stderr)
    errors = stdout.each_line("\n", :chomp => true).map do |line|
      JSON.parse(line).select { |key, _| ['data', 'type', 'details'].include?(key) }
    end
    assert_equal(6, errors.size)
    assert_includes(errors, 'data' => INVALID1, 'type' => 'required', 'details' => { 'missing_keys' => ['id'] })
    assert_includes(errors, 'data' => INVALID2, 'type' => 'required', 'details' => { 'missing_keys' => ['a'] })
    assert_includes(errors, 'data' => INVALID3['a'], 'type' => 'string')
    assert_includes(errors, 'data' => INVALID4['id'], 'type' => 'integer')
    assert_includes(errors, 'data' => INVALID5, 'type' => 'required', 'details' => { 'missing_keys' => ['id'] })
    assert_includes(errors, 'data' => INVALID5, 'type' => 'required', 'details' => { 'missing_keys' => ['a'] })
  end

  def test_max_errors
    tmp_json(INVALID1, INVALID2, INVALID3, INVALID4, INVALID5) do |*paths|
      stdout, stderr, status = exe('-e0', SCHEMA1, *paths)
      refute_predicate(status, :success?)
      assert_empty(stderr)
      assert_empty(stdout)

      stdout, stderr, status = exe('--errors', '0', SCHEMA1, *paths)
      refute_predicate(status, :success?)
      assert_empty(stderr)
      assert_empty(stdout)

      stdout, stderr, status = exe('--errors', '1', SCHEMA1, *paths)
      refute_predicate(status, :success?)
      assert_empty(stderr)
      assert_equal(1, stdout.split("\n").size)

      stdout, stderr, status = exe('--errors', '2', SCHEMA1, *paths)
      refute_predicate(status, :success?)
      assert_empty(stderr)
      assert_equal(2, stdout.split("\n").size)

      stdout, stderr, status = exe('-e2', SCHEMA1, *paths)
      refute_predicate(status, :success?)
      assert_empty(stderr)
      assert_equal(2, stdout.split("\n").size)

      stdout, stderr, status = exe('--errors', '10', SCHEMA1, *paths)
      refute_predicate(status, :success?)
      assert_empty(stderr)
      assert_equal(6, stdout.split("\n").size)
    end
  end

  def test_stdin
    schema = {
      'type' => 'object',
      'properties' => {
        'id' => {
          'type' => 'integer'
        }
      }
    }
    valid_data = { 'id' => 1 }
    invalid_data = { 'id' => 'invalid' }

    tmp_json(schema, valid_data, invalid_data) do |schema_path, valid_path, invalid_path|
      stdout, stderr, status = exe('-', valid_path, :stdin_data => JSON.generate(schema))
      assert_predicate(status, :success?)
      assert_empty(stderr)
      assert_empty(stdout)

      stdout, stderr, status = exe('-', valid_path, invalid_path, :stdin_data => JSON.generate(schema))
      refute_predicate(status, :success?)
      assert_empty(stderr)
      refute_empty(stdout)

      stdout, stderr, status = exe(schema_path, valid_path, '-', :stdin_data => JSON.generate(valid_data))
      assert_predicate(status, :success?)
      assert_empty(stderr)
      assert_empty(stdout)

      stdout, stderr, status = exe(schema_path, valid_path, '-', :stdin_data => JSON.generate(invalid_data))
      refute_predicate(status, :success?)
      assert_empty(stderr)
      refute_empty(stdout)

      stdout, stderr, status = exe('-e0', schema_path, invalid_path, '-', :stdin_data => JSON.generate(valid_data))
      refute_predicate(status, :success?)
      assert_empty(stderr)
      assert_empty(stdout)

      stdout, stderr, status = exe(schema_path, '-', valid_path, :stdin_data => JSON.generate(valid_data))
      assert_predicate(status, :success?)
      assert_empty(stderr)
      assert_empty(stdout)

      stdout, stderr, status = exe(schema_path, '-', valid_path, :stdin_data => JSON.generate(invalid_data))
      refute_predicate(status, :success?)
      assert_empty(stderr)
      refute_empty(stdout)

      stdout, stderr, status = exe('-e0', schema_path, '-', invalid_path, :stdin_data => JSON.generate(valid_data))
      refute_predicate(status, :success?)
      assert_empty(stderr)
      assert_empty(stdout)
    end
  end

private

  def exe(*args, **kwargs)
    env = {
      'GEM_HOME' => Gem.dir,
      'GEM_PATH' => [GEM_PATH, *Gem.path].uniq.join(File::PATH_SEPARATOR),
      'GEM_SPEC_CACHE' => Gem.spec_cache_dir,
      'RUBYOPT' => nil # prevent bundler/setup
    }
    Open3.capture3(env, CMD, *args, **kwargs)
  end

  def tmp_json(*json)
    files = json.map do |data, index|
      file = Tempfile.new(['data', '.json'])
      file.sync = true
      file.write(JSON.generate(data))
      file
    end
    yield(*files.map(&:path))
  ensure
    files.each(&:close)
    files.each(&:unlink)
  end
end
