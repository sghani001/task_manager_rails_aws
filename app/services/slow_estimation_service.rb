class SlowEstimationService
  def self.call(title, description)
    # Simulate a slow external service call (e.g., AWS Lambda, ML model, etc.)
    # In production, this would be an actual API call
    sleep(5)  # Simulate 5 seconds of processing
    
    # Generate a simple estimate based on description length
    word_count = description.to_s.split.length
    
    case word_count
    when 0..10
      "30 min"
    when 11..30
      "1-2 hours"
    when 31..50
      "2-4 hours"
    else
      "1 day"
    end
  end
end
