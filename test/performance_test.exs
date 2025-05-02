defmodule ExFsrs.PerformanceTest do
  use ExUnit.Case, async: true

  @tag timeout: 120_000 # 2 minutes
  @tag :performance
  test "simulate many reviews over long time period" do
    scheduler = ExFsrs.Scheduler.new()
    now = DateTime.utc_now()

    # Create new card
    card = ExFsrs.new()

    # Simulate 1000 days of reviews
    {final_card, stats, _final_now} = Enum.reduce(1..1000, {card, %{days: 0, reviews: 0}, now}, fn _, {current_card, stats, now} ->
      # If card is due for review
      if DateTime.compare(current_card.due, now) in [:lt, :eq] do
        # Generate a rating based on retrievability
        # The better the retrievability, the more likely to get a good rating
        retrievability = ExFsrs.get_retrievability(current_card, now)
        rating = cond do
          :rand.uniform() > retrievability + 0.1 -> :again
          :rand.uniform() > retrievability + 0.3 -> :hard
          :rand.uniform() > retrievability + 0.6 -> :good
          true -> :easy
        end

        # Review the card
        {updated_card, _} = ExFsrs.review_card(current_card, rating, now)

        # Advance time to next day
        next_now = DateTime.add(now, 1, :day)

        {updated_card, %{days: stats.days + 1, reviews: stats.reviews + 1}, next_now}
      else
        # Card not due, just advance time
        next_now = DateTime.add(now, 1, :day)

        {current_card, %{days: stats.days + 1, reviews: stats.reviews}, next_now}
      end
    end)

    # Verify results
    IO.puts("Simulated #{stats.days} days with #{stats.reviews} reviews")
    IO.puts("Final stability: #{final_card.stability}")
    IO.puts("Final difficulty: #{final_card.difficulty}")

    # Check that card eventually reaches at least some stability
    assert final_card.stability > 100.0, "Card should have high stability after many reviews"
  end

  @tag :benchmark
  test "benchmark basic operations" do
    # Create scheduler and cards for benchmarking
    scheduler = ExFsrs.Scheduler.new()
    now = DateTime.utc_now()
    learning_card = ExFsrs.new(state: :learning, step: 0)
    review_card = ExFsrs.new(
      state: :review,
      stability: 10.0,
      difficulty: 5.0,
      last_review: DateTime.add(now, -10, :day)
    )
    relearning_card = ExFsrs.new(
      state: :relearning,
      step: 0,
      stability: 5.0,
      difficulty: 7.0
    )

    # Benchmark card creation
    {time_new, _} = :timer.tc(fn -> Enum.each(1..1000, fn _ -> ExFsrs.new() end) end)

    # Benchmark reviewing learning card
    {time_learning, _} = :timer.tc(fn ->
      Enum.each(1..1000, fn _ ->
        ExFsrs.Scheduler.review_card(scheduler, learning_card, :good, now)
      end)
    end)

    # Benchmark reviewing review card
    {time_review, _} = :timer.tc(fn ->
      Enum.each(1..1000, fn _ ->
        ExFsrs.Scheduler.review_card(scheduler, review_card, :good, now)
      end)
    end)

    # Benchmark reviewing relearning card
    {time_relearning, _} = :timer.tc(fn ->
      Enum.each(1..1000, fn _ ->
        ExFsrs.Scheduler.review_card(scheduler, relearning_card, :good, now)
      end)
    end)

    IO.puts("Benchmark results (microseconds per 1000 operations):")
    IO.puts("  Card creation: #{time_new}")
    IO.puts("  Learning review: #{time_learning}")
    IO.puts("  Review review: #{time_review}")
    IO.puts("  Relearning review: #{time_relearning}")

    # All operations should be reasonably fast
    assert time_new < 100_000, "Card creation should be fast"
    assert time_learning < 1_000_000, "Learning review should be fast"
    assert time_review < 1_000_000, "Review review should be fast"
    assert time_relearning < 1_000_000, "Relearning review should be fast"
  end
end
