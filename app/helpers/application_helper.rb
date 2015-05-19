include TweetButton

module ApplicationHelper
  # If input is empty string or nil, returns string "&nbsp;".
  # Otherwise, cleans input using html_escape and returns resulting
  # string.
  #
  # Useful for forcing a table cell to have content, which forces CSS
  # styles for table cell to display in browsers (namely IE) where
  # they wouldn't if the cell were completely empty.
  def empty2nbsp(input, escape_input = true)
    if input.blank?
      return raw('&nbsp;')
    else
      if escape_input
        return html_escape(input)
      else
        return input
      end
    end
  end

  def format_boolean_as_yes_no(boolean)
    if boolean
      return 'Yes'
    else
      return 'No'
    end
  end

  def format_boolean_as_present(boolean)
    if boolean
      return 'Available'
    else
      return 'None available'
    end
  end

  def format_date(date)
    return date.strftime('%m / %d / %Y')
  rescue Exception => e
    return nil
  end

  def format_datetime(datetime)
    return datetime.strftime('%m / %d / %Y %l:%M:%S %P')
  rescue Exception => e
    return nil
  end

  def format_email_in_sidebar(email)
    return email.gsub(/(@)/, "@\r").delete(' ')
  rescue Exception => e
    return nil
  end

  # Truncates input string (to number of words specified, using word
  # boundaries) and returns resulting string.
  def truncate_words(text, length = 20, end_string = ' ...')
    if text.nil?
      return ''
    else
      words = text.split
      return words[0..(length - 1)].join(' ') + (words.length > length ? end_string : '')
    end
  end

  # Since Kaminari needs a "pagination object" to operate on, it is essential to turn a single
  # object into an Array that Kaminari can use.
  # def pagify(object)
  #   return Kaminari.paginate_array(Array[object])
  # end

  # Utility method for cleaning up xml fragments
  def tidy(str)
    fail ArgumentError unless str.is_a?(String)
    xml = Nokogiri::XML(str)
    fail ArgumentError unless xml.is_a?(Nokogiri::XML::Document)
    temp_str = xml.human
    xml2 = Nokogiri::XML(temp_str)
    xml2.root.to_s
  end
end
