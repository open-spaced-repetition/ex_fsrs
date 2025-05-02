defmodule ExFsrs.IntegrationTest do
  use ExUnit.Case, async: true

  describe "complete learning flow" do
    test "follows typical learning progression from new card to review" do
      # Create a new card
      card = ExFsrs.new()

      # First review with "good" rating
      {card, log1} = ExFsrs.review_card(card, :good)
      assert card.state == :learning
      assert card.step == 1
      assert card.stability != nil
      assert card.difficulty != nil
      assert log1.rating == :good

      # Move time forward 10 minutes
      now = DateTime.add(card.due, 1, :minute) # Just after due

      # Second review with "good" rating, should move to review state
      {card, log2} = ExFsrs.review_card(card, :good, now)
      assert card.state == :review
      assert card.step == nil
      assert card.stability > log1.card.stability
      assert log2.rating == :good

      # Move time forward beyond due date
      review_time = DateTime.add(card.due, 1, :day)

      # Review again with "again" rating, should move to relearning state
      {card, log3} = ExFsrs.review_card(card, :again, review_time)
      assert card.state == :relearning
      assert card.step == 0
      assert card.stability < log2.card.stability
      assert card.difficulty > log2.card.difficulty
      assert log3.rating == :again

      # Move time forward 10 minutes
      relearning_time = DateTime.add(card.due, 1, :minute)

      # Review with "good" rating, should move back to review state
      {card, log4} = ExFsrs.review_card(card, :good, relearning_time)
      assert card.state == :review
      assert card.step == nil
      assert card.stability > log3.card.stability
      assert log4.rating == :good

      # Due date should be days in future
      days_until_due = DateTime.diff(card.due, relearning_time, :day)
      assert days_until_due > 0
    end
  end

  describe "serialization and deserialization" do
    test "round-trip card through map conversion" do
      # Create and review a card
      card = ExFsrs.new()
      {reviewed_card, _} = ExFsrs.review_card(card, :good)

      # Convert to map and back
      map = ExFsrs.to_map(reviewed_card)
      restored_card = ExFsrs.from_map(map)

      # Verify all fields match
      assert restored_card.card_id == reviewed_card.card_id
      assert restored_card.state == reviewed_card.state
      assert restored_card.step == reviewed_card.step
      assert restored_card.stability == reviewed_card.stability
      assert restored_card.difficulty == reviewed_card.difficulty
      assert DateTime.to_iso8601(restored_card.due) == DateTime.to_iso8601(reviewed_card.due)
      assert DateTime.to_iso8601(restored_card.last_review) == DateTime.to_iso8601(reviewed_card.last_review)
    end

    test "round-trip review log through map conversion" do
      # Create and review a card
      card = ExFsrs.new()
      {reviewed_card, log} = ExFsrs.review_card(card, :good)

      # Convert log to map and back
      log_struct = ExFsrs.ReviewLog.new(reviewed_card, :good, log.review_datetime, 1000)
      map = ExFsrs.ReviewLog.to_map(log_struct)
      restored_log = ExFsrs.ReviewLog.from_map(map)

      # Verify fields match
      assert restored_log.card.card_id == log_struct.card.card_id
      assert restored_log.rating == log_struct.rating
      assert DateTime.to_date(restored_log.review_datetime) == DateTime.to_date(log_struct.review_datetime)
      assert DateTime.to_time(restored_log.review_datetime) |> Time.truncate(:second) ==
             DateTime.to_time(log_struct.review_datetime) |> Time.truncate(:second)
      assert restored_log.review_duration == log_struct.review_duration
    end
  end

  describe "complex stability calculations" do
    test "stability increases with consecutive good reviews" do
      card = ExFsrs.new()

      # Initial review
      {card, _} = ExFsrs.review_card(card, :good)
      initial_stability = card.stability

      # Wait until due date
      now = DateTime.add(card.due, 1, :minute)
      {card, _} = ExFsrs.review_card(card, :good, now)
      second_stability = card.stability

      # Wait until due date again
      now = DateTime.add(card.due, 1, :minute)
      {card, _} = ExFsrs.review_card(card, :good, now)
      third_stability = card.stability

      # Stability should increase with each review
      assert second_stability > initial_stability
      assert third_stability > second_stability
    end

    test "stability decreases after lapse and recovers with good reviews" do
      card = ExFsrs.new()

      # Initial review
      {card, _} = ExFsrs.review_card(card, :good)
      # Move to review state
      now = DateTime.add(card.due, 1, :minute)
      {card, _} = ExFsrs.review_card(card, :good, now)
      initial_stability = card.stability

      # Lapse with "again" rating
      now = DateTime.add(card.due, 1, :day)
      {card, _} = ExFsrs.review_card(card, :again, now)
      lapsed_stability = card.stability

      # Stability should decrease after lapse
      assert lapsed_stability < initial_stability

      # Recover with "good" rating
      now = DateTime.add(card.due, 1, :minute)
      {card, _} = ExFsrs.review_card(card, :good, now)
      recovery_stability = card.stability

      # Stability should increase after recovery
      assert recovery_stability > lapsed_stability
    end
  end
end
