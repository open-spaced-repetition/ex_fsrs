defmodule ExFsrs.SchedulerTest do
  use ExUnit.Case, async: true
  doctest ExFsrs.Scheduler

  describe "new/1" do
    test "creates new scheduler with default parameters" do
      scheduler = ExFsrs.Scheduler.new()

      assert length(scheduler.parameters) == 19
      assert scheduler.desired_retention == 0.9
      assert scheduler.learning_steps == [1.0, 10.0]
      assert scheduler.relearning_steps == [10.0]
      assert scheduler.maximum_interval == 36500
      assert scheduler.enable_fuzzing == true
    end

    test "creates new scheduler with custom parameters" do
      custom_params = List.duplicate(1.0, 19)
      scheduler = ExFsrs.Scheduler.new(
        parameters: custom_params,
        desired_retention: 0.8,
        learning_steps: [5.0, 15.0],
        relearning_steps: [20.0],
        maximum_interval: 1000,
        enable_fuzzing: false
      )

      assert scheduler.parameters == custom_params
      assert scheduler.desired_retention == 0.8
      assert scheduler.learning_steps == [5.0, 15.0]
      assert scheduler.relearning_steps == [20.0]
      assert scheduler.maximum_interval == 1000
      assert scheduler.enable_fuzzing == false
    end
  end

  describe "review_card/5" do
    setup do
      scheduler = ExFsrs.Scheduler.new(enable_fuzzing: false)
      now = DateTime.utc_now()

      {:ok, scheduler: scheduler, now: now}
    end

    test "reviews new learning card with 'again' rating", %{scheduler: scheduler, now: now} do
      card = ExFsrs.new(state: :learning, step: 0)

      {updated_card, log} = ExFsrs.Scheduler.review_card(scheduler, card, :again, now)

      assert updated_card.state == :learning
      assert updated_card.step == 0
      assert updated_card.stability != nil
      assert updated_card.difficulty != nil
      assert updated_card.last_review == now
      assert DateTime.diff(updated_card.due, now, :minute) == 1

      assert log.rating == :again
      assert log.review_datetime == now
    end

    test "reviews new learning card with 'hard' rating", %{scheduler: scheduler, now: now} do
      card = ExFsrs.new(state: :learning, step: 0)

      {updated_card, _log} = ExFsrs.Scheduler.review_card(scheduler, card, :hard, now)

      assert updated_card.state == :learning
      assert updated_card.step == 0
      assert updated_card.stability != nil
      assert updated_card.difficulty != nil

      # Due in 1 to 6 minutes (depending on learning_steps and calculation)
      minutes_until_due = DateTime.diff(updated_card.due, now, :minute)
      assert minutes_until_due >= 1
      assert minutes_until_due <= 6
    end

    test "reviews new learning card with 'good' rating", %{scheduler: scheduler, now: now} do
      card = ExFsrs.new(state: :learning, step: 0)

      {updated_card, _log} = ExFsrs.Scheduler.review_card(scheduler, card, :good, now)

      assert updated_card.state == :learning
      assert updated_card.step == 1
      assert updated_card.stability != nil
      assert updated_card.difficulty != nil

      # Due in approximately 10 minutes
      assert DateTime.diff(updated_card.due, now, :minute) == 10
    end

    test "reviews new learning card with 'easy' rating", %{scheduler: scheduler, now: now} do
      card = ExFsrs.new(state: :learning, step: 0)

      {updated_card, _log} = ExFsrs.Scheduler.review_card(scheduler, card, :easy, now)

      assert updated_card.state == :review
      assert updated_card.step == nil
      assert updated_card.stability != nil
      assert updated_card.difficulty != nil

      # Due in at least 1 day (converted to minutes)
      assert DateTime.diff(updated_card.due, now, :day) >= 1
    end
  end

  describe "review_card/5 for review state" do
    setup do
      scheduler = ExFsrs.Scheduler.new(enable_fuzzing: false)
      now = DateTime.utc_now()
      card = ExFsrs.new(
        state: :review,
        stability: 10.0,
        difficulty: 5.0,
        last_review: DateTime.add(now, -10, :day),
        due: now
      )

      {:ok, scheduler: scheduler, now: now, card: card}
    end

    test "reviews review card with 'again' rating", %{scheduler: scheduler, now: now, card: card} do
      {updated_card, _log} = ExFsrs.Scheduler.review_card(scheduler, card, :again, now)

      assert updated_card.state == :relearning
      assert updated_card.step == 0
      assert updated_card.stability != nil
      assert updated_card.difficulty > card.difficulty # Difficulty should increase

      # Due in approximately 10 minutes
      assert DateTime.diff(updated_card.due, now, :minute) == 10
    end

    test "reviews review card with 'hard' rating", %{scheduler: scheduler, now: now, card: card} do
      {updated_card, _log} = ExFsrs.Scheduler.review_card(scheduler, card, :hard, now)

      assert updated_card.state == :review
      assert updated_card.step == nil
      assert updated_card.stability != nil
      assert updated_card.difficulty > card.difficulty # Difficulty should increase

      # Due in future days (depends on stability calculation)
      assert DateTime.diff(updated_card.due, now, :day) > 0
    end

    test "reviews review card with 'good' rating", %{scheduler: scheduler, now: now, card: card} do
      {updated_card, _log} = ExFsrs.Scheduler.review_card(scheduler, card, :good, now)

      assert updated_card.state == :review
      assert updated_card.step == nil
      assert updated_card.stability > card.stability # Stability should increase

      # Due in future days (more than hard rating)
      assert DateTime.diff(updated_card.due, now, :day) > 0
    end

    test "reviews review card with 'easy' rating", %{scheduler: scheduler, now: now, card: card} do
      {updated_card, _log} = ExFsrs.Scheduler.review_card(scheduler, card, :easy, now)

      assert updated_card.state == :review
      assert updated_card.step == nil
      assert updated_card.stability > card.stability # Stability should increase significantly

      # Due in future days (more than good rating)
      days_until_due = DateTime.diff(updated_card.due, now, :day)
      assert days_until_due > 0
    end
  end

  describe "review_card/5 for relearning state" do
    setup do
      scheduler = ExFsrs.Scheduler.new(enable_fuzzing: false)
      now = DateTime.utc_now()
      card = ExFsrs.new(
        state: :relearning,
        step: 0,
        stability: 5.0,
        difficulty: 7.0,
        last_review: DateTime.add(now, -1, :day),
        due: now
      )

      {:ok, scheduler: scheduler, now: now, card: card}
    end

    test "reviews relearning card with 'again' rating", %{scheduler: scheduler, now: now, card: card} do
      {updated_card, _log} = ExFsrs.Scheduler.review_card(scheduler, card, :again, now)

      assert updated_card.state == :relearning
      assert updated_card.step == 0
      assert updated_card.stability < card.stability # Stability should decrease
      assert updated_card.difficulty > card.difficulty # Difficulty should increase

      # Due in approximately 10 minutes
      assert DateTime.diff(updated_card.due, now, :minute) == 10
    end

    test "reviews relearning card with 'hard' rating", %{scheduler: scheduler, now: now, card: card} do
      {updated_card, _log} = ExFsrs.Scheduler.review_card(scheduler, card, :hard, now)

      assert updated_card.state == :relearning
      assert updated_card.step == 0
      assert updated_card.stability != nil
      assert updated_card.difficulty > card.difficulty # Difficulty should increase

      # Due in 15 minutes (10 * 1.5)
      assert DateTime.diff(updated_card.due, now, :minute) == 15
    end

    test "reviews relearning card with 'good' rating", %{scheduler: scheduler, now: now, card: card} do
      {updated_card, _log} = ExFsrs.Scheduler.review_card(scheduler, card, :good, now)

      assert updated_card.state == :review
      assert updated_card.step == nil
      assert updated_card.stability != nil

      # Due in future days
      assert DateTime.diff(updated_card.due, now, :day) > 0
    end

    test "reviews relearning card with 'easy' rating", %{scheduler: scheduler, now: now, card: card} do
      {updated_card, _log} = ExFsrs.Scheduler.review_card(scheduler, card, :easy, now)

      assert updated_card.state == :review
      assert updated_card.step == nil
      assert updated_card.stability > card.stability # Stability should increase significantly

      # Due in future days (more than good rating)
      assert DateTime.diff(updated_card.due, now, :day) > 0
    end
  end

  describe "next_interval/2" do
    test "calculates proper interval based on stability" do
      scheduler = ExFsrs.Scheduler.new()

      # Test with different stability values
      intervals = [
        {1.0, 1 * 24 * 60}, # 1 day in minutes
        {5.0, 5 * 24 * 60}, # 5 days in minutes
        {25.0, 25 * 24 * 60}, # 25 days in minutes
        {100.0, 100 * 24 * 60} # 100 days in minutes
      ]

      Enum.each(intervals, fn {stability, expected_minutes} ->
        result = ExFsrs.Scheduler.next_interval(stability, scheduler)
        assert result == expected_minutes
      end)
    end

    test "respects maximum interval" do
      scheduler = ExFsrs.Scheduler.new(maximum_interval: 100)

      # Even with very high stability, should not exceed maximum
      result = ExFsrs.Scheduler.next_interval(1000.0, scheduler)
      assert result == 100 * 24 * 60 # 100 days in minutes
    end
  end

  describe "get_fuzzed_interval/1" do
    test "does not change intervals below 2.5" do
      # Test seed for reproducibility
      :rand.seed(:exsss, {1, 2, 3})

      result = ExFsrs.Scheduler.get_fuzzed_interval(2.0)
      assert result == 2
    end

    test "correctly fuzzes intervals between 2.5 and 7.0" do
      # Test seed for reproducibility
      :rand.seed(:exsss, {1, 2, 3})

      original = 5.0
      result = ExFsrs.Scheduler.get_fuzzed_interval(original)

      # Fuzz should be within 15% of original
      delta = original * 0.15
      assert result >= (original - delta)
      assert result <= (original + delta)
    end

    test "correctly fuzzes intervals between 7.0 and 20.0" do
      # Test seed for reproducibility
      :rand.seed(:exsss, {1, 2, 3})

      original = 10.0
      result = ExFsrs.Scheduler.get_fuzzed_interval(original)

      # Fuzz should be within 10% of original
      delta = original * 0.1
      assert result >= (original - delta)
      assert result <= (original + delta)
    end

    test "correctly fuzzes intervals above 20.0" do
      # Test seed for reproducibility
      :rand.seed(:exsss, {1, 2, 3})

      original = 30.0
      result = ExFsrs.Scheduler.get_fuzzed_interval(original)

      # Fuzz should be within 5% of original
      delta = original * 0.05
      assert result >= (original - delta)
      assert result <= (original + delta)
    end
  end

  # Tests for private functions using function capture
  describe "internal utility functions" do
    test "rating_to_number/1 converts rating atoms to numbers" do
      rating_to_number = :erlang.fun_to_list(&ExFsrs.Scheduler.rating_to_number/1)

      assert ExFsrs.Scheduler.rating_to_number(:again) == 1
      assert ExFsrs.Scheduler.rating_to_number(:hard) == 2
      assert ExFsrs.Scheduler.rating_to_number(:good) == 3
      assert ExFsrs.Scheduler.rating_to_number(:easy) == 4
    end
  end
end
