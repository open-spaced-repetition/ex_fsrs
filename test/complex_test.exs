defmodule ExFsrsTest.Complex do
  def run do
    # Helper function to print card state in a nice format
    defmodule TestHelpers do
      def print_card_state(card, prefix \\ "") do
        IO.puts("#{prefix}State: #{card.state}")
        IO.puts("#{prefix}Step: #{card.step}")

        IO.puts(
          "#{prefix}Stability: #{if card.stability, do: Float.round(card.stability, 4), else: "nil"}"
        )

        IO.puts(
          "#{prefix}Difficulty: #{if card.difficulty, do: Float.round(card.difficulty, 4), else: "nil"}"
        )

        IO.puts("#{prefix}Due: #{card.due}")
        IO.puts("#{prefix}Days until due: #{DateTime.diff(card.due, DateTime.utc_now(), :day)}")
        IO.puts("#{prefix}Last review: #{card.last_review}")
      end
    end

    # Initialize scheduler with fuzzing disabled
    scheduler = ExFsrs.Scheduler.new(enable_fuzzing: false)

    IO.puts("\n" <> String.duplicate("=", 50))
    IO.puts("TEST 1: LEARNING STATE PROGRESSION")
    IO.puts(String.duplicate("=", 50))

    # Create card in learning state
    card = ExFsrs.new(state: :learning, step: 0)

    # Test sequence of ratings
    ratings = [:again, :hard, :good, :easy]

    Enum.reduce(ratings, card, fn rating, card ->
      IO.puts("\n" <> String.duplicate("-", 30))
      IO.puts("Rating: #{rating}")
      IO.puts(String.duplicate("-", 30))

      IO.puts("\nBefore review:")
      TestHelpers.print_card_state(card, "  ")

      {card, _} = ExFsrs.Scheduler.review_card(scheduler, card, rating)

      IO.puts("\nAfter review:")
      TestHelpers.print_card_state(card, "  ")

      card
    end)

    IO.puts("\n" <> String.duplicate("=", 50))
    IO.puts("TEST 2: REVIEW STATE WITH DIFFERENT RATINGS")
    IO.puts(String.duplicate("=", 50))

    # Create card in review state
    card =
      ExFsrs.new(
        state: :review,
        stability: 10.0,
        difficulty: 5.0,
        due: DateTime.add(DateTime.utc_now(), 10, :day)
      )

    # Test different ratings in review state
    review_ratings = [:again, :hard, :good, :easy]

    Enum.reduce(review_ratings, card, fn rating, card ->
      IO.puts("\n" <> String.duplicate("-", 30))
      IO.puts("Rating: #{rating}")
      IO.puts(String.duplicate("-", 30))

      IO.puts("\nBefore review:")
      TestHelpers.print_card_state(card, "  ")

      {card, _} = ExFsrs.Scheduler.review_card(scheduler, card, rating)

      IO.puts("\nAfter review:")
      TestHelpers.print_card_state(card, "  ")

      card
    end)

    IO.puts("\n" <> String.duplicate("=", 50))
    IO.puts("TEST 3: RELEARNING STATE")
    IO.puts(String.duplicate("=", 50))

    # Create card in relearning state
    card =
      ExFsrs.new(
        state: :relearning,
        step: 0,
        stability: 5.0,
        difficulty: 7.0,
        due: DateTime.add(DateTime.utc_now(), 1, :day)
      )

    # Test different ratings in relearning state
    relearning_ratings = [:again, :hard, :good, :easy]

    Enum.reduce(relearning_ratings, card, fn rating, card ->
      IO.puts("\n" <> String.duplicate("-", 30))
      IO.puts("Rating: #{rating}")
      IO.puts(String.duplicate("-", 30))

      IO.puts("\nBefore review:")
      TestHelpers.print_card_state(card, "  ")

      {card, _} = ExFsrs.Scheduler.review_card(scheduler, card, rating)

      IO.puts("\nAfter review:")
      TestHelpers.print_card_state(card, "  ")

      card
    end)

    IO.puts("\n" <> String.duplicate("=", 50))
    IO.puts("TEST 4: EXTREME VALUES")
    IO.puts(String.duplicate("=", 50))

    # Test with extreme stability and difficulty values
    card =
      ExFsrs.new(
        state: :review,
        stability: 1000.0,
        difficulty: 10.0,
        due: DateTime.add(DateTime.utc_now(), 1000, :day)
      )

    IO.puts("\nBefore review:")
    TestHelpers.print_card_state(card, "  ")

    {card, _} = ExFsrs.Scheduler.review_card(scheduler, card, :good)

    IO.puts("\nAfter review:")
    TestHelpers.print_card_state(card, "  ")
  end
end

# Run test automatically when file is loaded
# ExFsrsTest.Complex.run()
