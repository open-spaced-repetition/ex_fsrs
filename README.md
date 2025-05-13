# ExFsrs

**An Elixir implementation of FSRS (Free Spaced Repetition Scheduler in Elixir)**

[![Elixir](https://img.shields.io/badge/Lang-Elixir-purple.svg)](https://elixir-lang.org/)

A flexible spaced repetition scheduling implementation in Elixir. This library is designed to help you schedule reviews in an optimal way, taking into account card difficulty, stability, and user feedback. The code here demonstrates how to compute the next intervals for flashcards using advanced scheduling techniques, including fuzzing intervals to avoid predictable review dates.

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Usage](#usage)
- [Modules](#modules)
  - [ExFsrs](#exfsrs)
  - [Scheduler](#scheduler)
  - [ReviewLog](#reviewlog)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

This project implements a variant of the [FSRS (Free Spaced Repetition Schedule)](https://www.supermemo.com/en/archives1990-2015/english/ol/sm2) algorithm in Elixir. The code is intended for advanced spaced repetition systems, allowing dynamic interval calculation, difficulty tracking, state transitions, and fuzzing intervals to avoid "review day clumping".

Key features:
- **Adaptive scheduling** based on a card's difficulty, stability, and prior performance.
- **Fuzzing (optional)** to randomize intervals, preventing overly predictable schedules.
- **Learning, Review, Relearning states** with dedicated logic for each phase.
- **Integration** with standard Elixir structs and concurrency if needed.

---

## Installation

If you want to include this functionality in your own Elixir application, you can integrate it as a local dependency or copy the modules directly into your project. For a typical Elixir project:

1. Add the project as a dependency in your `mix.exs` (if you have a private git repository or local path, adjust accordingly):
   ```elixir
   def deps do
     [
       {:ex_fsrs, "~> 0.1.0", git: "https://github.com/open-spaced-repetition/ex_fsrs"}
     ]
   end
   ```

2. Fetch and compile dependencies:
   ```elixir
   mix deps.get
   mix compile
   ```

---

## Usage   

Below is a quick example demonstrating how you might use the core ExFsrs module to process a review for a given card:

```elixir
# Create a new card
card = ExFsrs.new(state: :learning, step: 0)

# Review the card with a rating
{updated_card, review_log} = ExFsrs.review_card(card, :good)

# Or use the scheduler directly with custom parameters
scheduler = ExFsrs.Scheduler.new(
  parameters: [0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575, 0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621],
  desired_retention: 0.9,
  learning_steps: [1.0, 10.0],
  relearning_steps: [10.0],
  maximum_interval: 36500,
  enable_fuzzing: true
)

{updated_card, review_log} = ExFsrs.Scheduler.review_card(scheduler, card, :good)
```

What happens under the hood?

1. **Card State Update**  
   The card's state is updated based on the rating and current state (learning, review, or relearning).

2. **Difficulty & Stability Calculation**  
   The scheduler computes new difficulty and stability values based on the rating and time since last review.

3. **Interval Computation**  
   Based on the new difficulty, stability, and rating, the next review interval is calculated. If fuzzing is enabled, the interval may be slightly randomized.

4. **Logging**  
   A ReviewLog is created to track the review outcome, including the rating, review datetime, and updated card state.

---

## Modules

### ExFsrs
The main module that provides the card struct and basic review functionality.

```elixir
defmodule ExFsrs do
  @type t :: %__MODULE__{
    card_id: integer(),
    state: :learning | :review | :relearning,
    step: integer() | nil,
    stability: float() | nil,
    difficulty: float() | nil,
    due: DateTime.t(),
    last_review: DateTime.t() | nil
  }

  defstruct [
    :card_id,
    :state,
    :step,
    :stability,
    :difficulty,
    :due,
    :last_review
  ]
end
```

### Scheduler
Handles the core spaced repetition algorithm, including interval calculation and state transitions.

```elixir
defmodule ExFsrs.Scheduler do
  @type t :: %__MODULE__{
    parameters: [float()],
    desired_retention: float(),
    learning_steps: [float()],
    relearning_steps: [float()],
    maximum_interval: integer(),
    enable_fuzzing: boolean()
  }

  defstruct [
    :parameters,
    :desired_retention,
    :learning_steps,
    :relearning_steps,
    :maximum_interval,
    :enable_fuzzing
  ]
end
```

### ReviewLog
Tracks the outcome of a review, including the rating and updated card state.

```elixir
defmodule ExFsrs.ReviewLog do
  @type t :: %__MODULE__{
    card: ExFsrs.t(),
    rating: ExFsrs.rating(),
    review_datetime: DateTime.t(),
    review_duration: integer() | nil
  }

  defstruct [
    :card,
    :rating,
    :review_datetime,
    :review_duration
  ]
end
```

---

## Testing

The library comes with a test suite to ensure functionality works as expected.

### Running Standard Tests

To run the entire test suite:

```bash
mix test
```

This will execute all tests, including unit tests for individual modules and integration tests.

You can also run specific test files:

```bash
mix test test/scheduler_test.exs
```

Or run tests with a specific tag:

```bash
mix test --only performance
```

### Running Complex Interactive Tests

For a more detailed demonstration of how the algorithm works with different card states and ratings, you can run the Complex test:

```bash
# Start an interactive Elixir shell with the project loaded
iex -S mix

# Load the complex test file
c("test/complex_test.exs")

# Run the test function
ExFsrsTest.Complex.run()
```

This will output detailed information about card state transitions, including:
- How cards move through learning, review, and relearning states
- How difficulty and stability change over time
- How different ratings (:again, :hard, :good, :easy) affect scheduling
- Due dates and intervals for future reviews

The complex test is particularly useful for visualizing how the algorithm behaves under different conditions and can be a helpful educational tool for understanding the FSRS system.

---

## Contributing

**Contributions are welcome!** If you would like to fix bugs or add new features:

1. Fork the repository
2. Create a new branch
3. Make your changes and commit them
4. Push to your fork
5. Create a pull request    

Please ensure you include tests where appropriate.

---

## License
This project is available as open source under the terms of the **MIT License**. Feel free to use it, distribute it, and contribute.

---
**Happy coding**. If you have any questions or want to share how you're using this library, feel free to open an issue or pull request.
