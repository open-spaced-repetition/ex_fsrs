defmodule ExFsrs.ReviewLogTest do
  use ExUnit.Case, async: true
  doctest ExFsrs.ReviewLog

  describe "new/4" do
    test "creates a new review log with all parameters" do
      card = ExFsrs.new()
      now = DateTime.utc_now()
      duration = 1000

      log = ExFsrs.ReviewLog.new(card, :good, now, duration)

      assert log.card == card
      assert log.rating == :good
      assert log.review_datetime == now
      assert log.review_duration == duration
    end

    test "creates a new review log with default values" do
      card = ExFsrs.new()

      log = ExFsrs.ReviewLog.new(card, :good)

      assert log.card == card
      assert log.rating == :good
      assert %DateTime{} = log.review_datetime
      assert log.review_duration == nil
    end
  end

  describe "to_map/1" do
    test "converts review log to map with all fields" do
      card = ExFsrs.new(card_id: 12345)
      now = DateTime.utc_now()
      duration = 1000

      log = ExFsrs.ReviewLog.new(card, :good, now, duration)
      map = ExFsrs.ReviewLog.to_map(log)

      assert map["card"]["card_id"] == 12345
      assert map["rating"] == :good
      assert map["review_datetime"] == DateTime.to_iso8601(now)
      assert map["review_duration"] == duration
    end
  end

  describe "from_map/1" do
    test "creates review log from map" do
      now = DateTime.utc_now()
      now_iso = DateTime.to_iso8601(now)
      card_map = %{
        "card_id" => 12345,
        "state" => "review",
        "step" => nil,
        "stability" => 10.0,
        "difficulty" => 5.0,
        "due" => now_iso,
        "last_review" => now_iso
      }

      map = %{
        "card" => card_map,
        "rating" => "good",
        "review_datetime" => now_iso,
        "review_duration" => 1000
      }

      log = ExFsrs.ReviewLog.from_map(map)

      assert log.card.card_id == 12345
      assert log.rating == :good
      assert DateTime.to_iso8601(log.review_datetime) == now_iso
      assert log.review_duration == 1000
    end

    test "raises error on invalid review_datetime" do
      card_map = %{
        "card_id" => 12345,
        "state" => "review",
        "step" => nil,
        "stability" => 10.0,
        "difficulty" => 5.0,
        "due" => DateTime.to_iso8601(DateTime.utc_now()),
        "last_review" => nil
      }

      map = %{
        "card" => card_map,
        "rating" => "good",
        "review_datetime" => "invalid date",
        "review_duration" => 1000
      }

      assert_raise RuntimeError, ~r/Invalid ISO8601 datetime format/, fn ->
        ExFsrs.ReviewLog.from_map(map)
      end
    end
  end
end
