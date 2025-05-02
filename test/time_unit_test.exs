defmodule ExFsrs.TimeUnitTest do
  use ExUnit.Case, async: true

  describe "interval time units" do
    test "learning steps are in minutes" do
      scheduler = ExFsrs.Scheduler.new()

      # Default learning steps should be [1.0, 10.0] minutes
      assert scheduler.learning_steps == [1.0, 10.0]

      # Create a card and review with 'good'
      card = ExFsrs.new(state: :learning, step: 0)
      now = DateTime.utc_now()
      {updated_card, _} = ExFsrs.Scheduler.review_card(scheduler, card, :good, now)

      # Due date should be exactly 10 minutes later (step 1)
      minutes_diff = DateTime.diff(updated_card.due, now, :minute)
      assert minutes_diff == 10
    end

    test "relearning steps are in minutes" do
      scheduler = ExFsrs.Scheduler.new()

      # Default relearning steps should be [10.0] minutes
      assert scheduler.relearning_steps == [10.0]

      # Create a card in relearning state
      card = ExFsrs.new(state: :relearning, step: 0, stability: 5.0, difficulty: 5.0)
      now = DateTime.utc_now()

      # Review with 'again'
      {updated_card, _} = ExFsrs.Scheduler.review_card(scheduler, card, :again, now)

      # Due date should be exactly 10 minutes later
      minutes_diff = DateTime.diff(updated_card.due, now, :minute)
      assert minutes_diff == 10
    end

    test "next_interval returns interval in minutes" do
      scheduler = ExFsrs.Scheduler.new()

      # Test with stability of 1.0, which should return 1 day
      interval_minutes = ExFsrs.Scheduler.next_interval(1.0, scheduler)
      # 1 day in minutes
      assert interval_minutes == 24 * 60
    end
  end

  describe "fuzzing behavior" do
    test "enable_fuzzing affects interval calculations" do
      # Create two schedulers, one with fuzzing enabled and one without
      scheduler_no_fuzz = ExFsrs.Scheduler.new(enable_fuzzing: false)
      scheduler_with_fuzz = ExFsrs.Scheduler.new(enable_fuzzing: true)

      # Create a card for each scheduler
      now = DateTime.utc_now()

      card =
        ExFsrs.new(
          state: :review,
          stability: 25.0,
          difficulty: 5.0,
          last_review: DateTime.add(now, -30, :day)
        )

      # Use a fixed seed for reproducible tests
      :rand.seed(:exsss, {1, 2, 3})

      # Review both cards with 'good'
      {card_no_fuzz, _} = ExFsrs.Scheduler.review_card(scheduler_no_fuzz, card, :good, now)
      {card_with_fuzz, _} = ExFsrs.Scheduler.review_card(scheduler_with_fuzz, card, :good, now)

      # Due dates should be different when fuzzing is enabled
      no_fuzz_days = DateTime.diff(card_no_fuzz.due, now, :day)
      with_fuzz_days = DateTime.diff(card_with_fuzz.due, now, :day)

      assert no_fuzz_days != with_fuzz_days, "Fuzzing should change the interval"
    end
  end
end
