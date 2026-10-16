module DurationHelper
  # A short wait, the way one says it: « 45 s », « 2 min 10 s », « 1 h 05 ».
  def duration_in_words_short(seconds)
    seconds = seconds.to_i
    return "#{seconds} s" if seconds < 60

    minutes, rest = seconds.divmod(60)
    return (rest.zero? ? "#{minutes} min" : "#{minutes} min #{rest} s") if minutes < 60

    hours, minutes = minutes.divmod(60)
    format("%d h %02d", hours, minutes)
  end
end
