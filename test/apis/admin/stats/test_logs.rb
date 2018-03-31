require_relative "../../../test_helper"

class Test::Apis::Admin::Stats::TestLogs < Minitest::Test
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    super
    setup_server
    ElasticsearchHelper.clean_es_indices(["2014-11", "2015-01", "2015-03"])
  end

  def test_strips_api_keys_from_request_url_in_json
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :request_url => "http://127.0.0.1/with_api_key/?foo=bar&api_key=my_secret_key", :request_path => "/with_api_key/", :request_url_query => "foo=bar&api_key=my_secret_key", :request_query => { "foo" => "bar", "api_key" => "my_secret_key" }, :request_user_agent => unique_test_id)
    LogItem.gateway.refresh_index!

    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/logs.json", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "start_at" => "2015-01-13",
        "end_at" => "2015-01-18",
        "interval" => "day",
        "start" => "0",
        "length" => "10",
      },
    }))

    assert_response_code(200, response)
    body = response.body
    data = MultiJson.load(body)
    assert_equal(1, data["recordsTotal"], data)
    assert_equal("/with_api_key/?foo=bar", data["data"][0]["request_url"])
    assert_equal("foo=bar", data["data"][0]["request_url_query"])
    assert_equal({ "foo" => "bar" }, data["data"][0]["request_query"])
    refute_match("my_secret_key", body)
  end

  def test_strips_api_keys_from_request_url_in_csv
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :request_url => "http://127.0.0.1/with_api_key/?api_key=my_secret_key&foo=bar", :request_path => "/with_api_key/", :request_url_query => "api_key=my_secret_key&foo=bar", :request_query => { "foo" => "bar", "api_key" => "my_secret_key" }, :request_user_agent => unique_test_id)
    LogItem.gateway.refresh_index!

    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/logs.csv", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "start_at" => "2015-01-13",
        "end_at" => "2015-01-18",
        "interval" => "day",
        "start" => "0",
        "length" => "10",
      },
    }))

    assert_response_code(200, response)
    body = response.body
    assert_match(",http://127.0.0.1/with_api_key/?foo=bar,", body)
    refute_match("my_secret_key", body)
  end

  def test_downloading_csv_that_uses_scan_and_scroll_elasticsearch_query
    FactoryBot.create_list(:log_item, 1005, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :request_user_agent => unique_test_id)
    LogItem.gateway.refresh_index!

    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/logs.csv", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "search" => "",
        "start_at" => "2015-01-13",
        "end_at" => "2015-01-18",
        "interval" => "day",
      },
    }))

    assert_response_code(200, response)
    assert_equal("text/csv", response.headers["Content-Type"])
    assert_match("attachment; filename=\"api_logs (#{Time.now.utc.strftime("%b %-e %Y")}).csv\"", response.headers["Content-Disposition"])

    lines = response.body.split("\n")
    assert_equal("Time,Method,Host,URL,User,IP Address,Country,State,City,Status,Reason Denied,Response Time,Content Type,Accept Encoding,User Agent", lines[0])
    assert_equal(1006, lines.length, lines)
  end

  def test_query_builder_case_insensitive_defaults
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :request_user_agent => "MOZILLAAA-#{unique_test_id}")
    LogItem.gateway.refresh_index!

    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/logs.json", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "start_at" => "2015-01-13",
        "end_at" => "2015-01-18",
        "interval" => "day",
        "start" => "0",
        "length" => "10",
        "query" => '{"condition":"AND","rules":[{"id":"request_user_agent","field":"request_user_agent","type":"string","input":"text","operator":"begins_with","value":"Mozilla"}]}',
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(1, data["recordsTotal"])
    assert_equal("MOZILLAAA-#{unique_test_id}", data["data"][0]["request_user_agent"])
  end

  def test_query_builder_api_key_case_sensitive
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :api_key => "AbCDeF", :request_user_agent => unique_test_id)
    LogItem.gateway.refresh_index!

    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/logs.json", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "start_at" => "2015-01-13",
        "end_at" => "2015-01-18",
        "interval" => "day",
        "start" => "0",
        "length" => "10",
        "query" => '{"condition":"AND","rules":[{"id":"api_key","field":"api_key","type":"string","input":"text","operator":"begins_with","value":"AbCDeF"}]}',
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(1, data["recordsTotal"])
    assert_equal(unique_test_id, data["data"][0]["request_user_agent"])
  end

  def test_query_builder_nulls
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :request_user_agent => "#{unique_test_id}-null")
    FactoryBot.create(:log_item, :request_at => Time.parse("2015-01-16T06:06:28.816Z").utc, :gatekeeper_denied_code => "api_key_missing", :request_user_agent => "#{unique_test_id}-not-null")
    LogItem.gateway.refresh_index!

    response = Typhoeus.get("https://127.0.0.1:9081/admin/stats/logs.json", http_options.deep_merge(admin_session).deep_merge({
      :params => {
        "start_at" => "2015-01-13",
        "end_at" => "2015-01-18",
        "interval" => "day",
        "start" => "0",
        "length" => "10",
        "query" => '{"condition":"AND","rules":[{"id":"gatekeeper_denied_code","field":"gatekeeper_denied_code","type":"string","input":"select","operator":"is_not_null","value":null}]}',
      },
    }))

    assert_response_code(200, response)
    data = MultiJson.load(response.body)
    assert_equal(1, data["recordsTotal"])
    assert_equal("#{unique_test_id}-not-null", data["data"][0]["request_user_agent"])
  end
end
