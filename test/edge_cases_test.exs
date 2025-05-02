defmodule ExFsrs.EdgeCasesTest do
  use ExUnit.Case, async: true

  describe "edge cases in scheduler" do
    test "handles very high stability values" do
      scheduler = ExFsrs.Scheduler.new()
      now = DateTime.utc_now()

      # Create a card with extremely high stability
      card =
        ExFsrs.new(
          state: :review,
          # Very high stability
          stability: 1_000_000.0,
          difficulty: 5.0
        )

      # Review with 'good'
      {updated_card, _} = ExFsrs.Scheduler.review_card(scheduler, card, :good, now)

      # Due date should not exceed maximum interval
      days_until_due = DateTime.diff(updated_card.due, now, :day)
      assert days_until_due <= scheduler.maximum_interval
    end

    test "handles very low stability values" do
      scheduler = ExFsrs.Scheduler.new()
      now = DateTime.utc_now()

      # Create a card with extremely low stability
      card =
        ExFsrs.new(
          state: :review,
          # Very low stability
          stability: 0.1,
          difficulty: 5.0
        )

      # Review with 'good'
      {updated_card, _} = ExFsrs.Scheduler.review_card(scheduler, card, :good, now)

      # Due date should be at least 1 day
      days_until_due = DateTime.diff(updated_card.due, now, :day)
      assert days_until_due >= 1
    end

    test "handles nil stability and difficulty for learning card" do
      scheduler = ExFsrs.Scheduler.new()
      now = DateTime.utc_now()

      # Create a card with nil stability and difficulty
      card =
        ExFsrs.new(
          state: :learning,
          stability: nil,
          difficulty: nil
        )

      # Should not raise errors
      {updated_card, _} = ExFsrs.Scheduler.review_card(scheduler, card, :good, now)

      # Values should be initialized
      assert updated_card.stability != nil
      assert updated_card.difficulty != nil
    end

    test "handles empty learning steps" do
      scheduler = ExFsrs.Scheduler.new(learning_steps: [])
      now = DateTime.utc_now()

      # Create a learning card
      card = ExFsrs.new(state: :learning, step: 0)

      # Test all ratings
      Enum.each([:again, :hard, :good, :easy], fn rating ->
        # Should not raise errors
        {updated_card, _} = ExFsrs.Scheduler.review_card(scheduler, card, rating, now)

        # Card should move to review state due to empty learning steps
        assert updated_card.state == :review
      end)
    end

    test "handles empty relearning steps" do
      scheduler = ExFsrs.Scheduler.new(relearning_steps: [])
      now = DateTime.utc_now()

      # Create a review card
      card =
        ExFsrs.new(
          state: :review,
          stability: 10.0,
          difficulty: 5.0
        )

      # Review with 'again' should keep it in review state due to empty relearning steps
      {updated_card, _} = ExFsrs.Scheduler.review_card(scheduler, card, :again, now)

      assert updated_card.state == :review
    end
  end

  describe "boundary conditions" do
    test "difficulty is clamped between 1.0 and 10.0" do
      scheduler = ExFsrs.Scheduler.new()
      now = DateTime.utc_now()

      # Create a card with maximum difficulty
      max_card =
        ExFsrs.new(
          state: :review,
          stability: 10.0,
          difficulty: 10.0
        )

      # Even with 'again' rating, difficulty should not exceed 10.0
      {updated_max, _} = ExFsrs.Scheduler.review_card(scheduler, max_card, :again, now)
      assert updated_max.difficulty <= 10.0

      # Create a card with minimum difficulty
      min_card =
        ExFsrs.new(
          state: :review,
          stability: 10.0,
          difficulty: 1.0
        )

      # Even with 'easy' rating, difficulty should not go below 1.0
      {updated_min, _} = ExFsrs.Scheduler.review_card(scheduler, min_card, :easy, now)
      assert updated_min.difficulty >= 1.0
    end

    test "retrievability is between 0 and 1" do
      now = DateTime.utc_now()

      # Various test cases with different stability and days since review
      test_cases = [
        # Just reviewed, should be close to 1.0
        {10.0, 0},
        # Should be around 0.5
        {10.0, 10},
        # Should be close to 0.0
        {10.0, 100},
        # Low stability, should be around 0.5
        {1.0, 1},
        # High stability, should be close to 1.0
        {100.0, 10}
      ]

      Enum.each(test_cases, fn {stability, days} ->
        card =
          ExFsrs.new(
            state: :review,
            stability: stability,
            difficulty: 5.0,
            last_review: DateTime.add(now, -days, :day)
          )

        # Call private function via module function call
        retrievability = ExFsrs.get_retrievability(card, now)

        assert retrievability >= 0.0, "Retrievability should be >= 0"
        assert retrievability <= 1.0, "Retrievability should be <= 1"
      end)
    end
  end
end
