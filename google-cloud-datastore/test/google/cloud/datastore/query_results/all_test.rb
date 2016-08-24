# Copyright 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "helper"

describe Google::Cloud::Datastore::Dataset, :all do
  let(:project)     { "my-todo-project" }
  let(:credentials) { OpenStruct.new }
  let(:dataset)     { Google::Cloud::Datastore::Dataset.new(Google::Cloud::Datastore::Service.new(project, credentials)) }
  let(:first_run_query_req) do
    Google::Datastore::V1::RunQueryRequest.new(
      project_id: project,
      query: Google::Cloud::Datastore::Query.new.kind("Task").to_grpc
    )
  end
  let(:first_run_query_res) do
    run_query_res_entities = 25.times.map do |i|
      Google::Datastore::V1::EntityResult.new(
        entity: Google::Cloud::Datastore::Entity.new.tap do |e|
          e.key = Google::Cloud::Datastore::Key.new "ds-test", 1000+i
          e["name"] = "thingamajig"
        end.to_grpc,
        cursor: "result-cursor-1-#{i}".force_encoding("ASCII-8BIT")
      )
    end
    Google::Datastore::V1::RunQueryResponse.new(
      batch: Google::Datastore::V1::QueryResultBatch.new(
        entity_results: run_query_res_entities,
        more_results: :NOT_FINISHED,
        end_cursor: "second-page-cursor".force_encoding("ASCII-8BIT")
      )
    )
  end
  let(:next_run_query_req) do
    Google::Datastore::V1::RunQueryRequest.new(
      project_id: project,
      query: Google::Cloud::Datastore::Query.new.kind("Task").start(
        Google::Cloud::Datastore::Cursor.from_grpc("second-page-cursor")
      ).to_grpc
    )
  end
  let(:next_run_query_res) do
    run_query_res_entities = 25.times.map do |i|
      Google::Datastore::V1::EntityResult.new(
        entity: Google::Cloud::Datastore::Entity.new.tap do |e|
          e.key = Google::Cloud::Datastore::Key.new "ds-test", 2000+i
          e["name"] = "thingamajig"
        end.to_grpc,
        cursor: "result-cursor-2-#{i}".force_encoding("ASCII-8BIT")
      )
    end
    Google::Datastore::V1::RunQueryResponse.new(
      batch: Google::Datastore::V1::QueryResultBatch.new(
        entity_results: run_query_res_entities,
        more_results: :NO_MORE_RESULTS
      )
    )
  end

  before do
    dataset.service.mocked_datastore = Minitest::Mock.new
    dataset.service.mocked_datastore.expect :run_query, first_run_query_res, [first_run_query_req]
    dataset.service.mocked_datastore.expect :run_query, next_run_query_res, [next_run_query_req]
  end

  after do
    dataset.service.mocked_datastore.verify
  end

  it "run will fulfill a query and return an object that can paginate" do
    first_entities = dataset.run dataset.query("Task")

    first_entities.count.must_equal 25
    first_entities.each do |entity|
      entity.must_be_kind_of Google::Cloud::Datastore::Entity
    end
    first_entities.cursor_for(first_entities.first).must_equal Google::Cloud::Datastore::Cursor.from_grpc("result-cursor-1-0")
    first_entities.cursor_for(first_entities.last).must_equal  Google::Cloud::Datastore::Cursor.from_grpc("result-cursor-1-24")
    first_entities.each_with_cursor do |entity, cursor|
      entity.must_be_kind_of Google::Cloud::Datastore::Entity
      cursor.must_be_kind_of Google::Cloud::Datastore::Cursor
    end
    # can use the enumerator without passing a block...
    first_entities.each_with_cursor.map do |entity, cursor|
      [entity.key, cursor]
    end.each do |result, cursor|
      result.must_be_kind_of Google::Cloud::Datastore::Key
      cursor.must_be_kind_of Google::Cloud::Datastore::Cursor
    end
    first_entities.cursor.must_equal     Google::Cloud::Datastore::Cursor.from_grpc("second-page-cursor")
    first_entities.end_cursor.must_equal Google::Cloud::Datastore::Cursor.from_grpc("second-page-cursor")
    first_entities.more_results.must_equal :NOT_FINISHED
    assert first_entities.not_finished?
    refute first_entities.more_after_limit?
    refute first_entities.more_after_cursor?
    refute first_entities.no_more?

    assert first_entities.next?
    next_entities = first_entities.next

    next_entities.each do |entity|
      entity.must_be_kind_of Google::Cloud::Datastore::Entity
    end
    next_entities.cursor_for(next_entities.first).must_equal Google::Cloud::Datastore::Cursor.from_grpc("result-cursor-2-0")
    next_entities.cursor_for(next_entities.last).must_equal  Google::Cloud::Datastore::Cursor.from_grpc("result-cursor-2-24")
    next_entities.each_with_cursor do |entity, cursor|
      entity.must_be_kind_of Google::Cloud::Datastore::Entity
      cursor.must_be_kind_of Google::Cloud::Datastore::Cursor
    end
    # can use the enumerator without passing a block...
    next_entities.each_with_cursor.map do |entity, cursor|
      [entity.key, cursor]
    end.each do |result, cursor|
      result.must_be_kind_of Google::Cloud::Datastore::Key
      cursor.must_be_kind_of Google::Cloud::Datastore::Cursor
    end
    next_entities.cursor.must_be     :nil?
    next_entities.end_cursor.must_be :nil?
    next_entities.more_results.must_equal :NO_MORE_RESULTS
    refute next_entities.not_finished?
    refute next_entities.more_after_limit?
    refute next_entities.more_after_cursor?
    assert next_entities.no_more?

    refute next_entities.next?
  end

  it "run will fulfill a query and return an object that can paginate with all" do
    entities = dataset.run dataset.query("Task")
    entities.all.each do |entity|
      entity.must_be_kind_of Google::Cloud::Datastore::Entity
    end
  end

  it "run will fulfill a query and can use the all enumerator to get count" do
    entities = dataset.run dataset.query("Task")
    entities.all.count.must_equal 50
  end

  it "run will fulfill a query and can use the all enumerator to map results" do
    entities = dataset.run dataset.query("Task")
    entities.all.map(&:key).each do |result|
      result.must_be_kind_of Google::Cloud::Datastore::Key
    end
  end

  it "run will fulfill a query and return an object that can paginate with all_with_cursor" do
    entities = dataset.run dataset.query("Task")
    entities.all_with_cursor.each do |entity, cursor|
      entity.must_be_kind_of Google::Cloud::Datastore::Entity
      cursor.must_be_kind_of Google::Cloud::Datastore::Cursor
    end
  end
end
