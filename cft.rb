#!/usr/bin/ruby

# rather quick script to help crack Fallout 4 terminals

def common(str1, str2)
  count = 0
  str1.chars.each_with_index {|c, i|  count += 1 if c == str2.chars[i] }
  return count
end
# picks is {word => number}
def crack(list, picks={})
  scores = []

  list.each_with_index do |word, idx|
    next if picks[word]
    
    score = 0
    list.each_with_index do |word2, idx2|
      next if idx == idx2
      s = common(word, word2)
      if picks[word2] && picks[word2] != s
        score = -1
      else
        if (score >= 0)
          score += 1 if(s > 0)
          score += s/2
        end
      end
    end
    scores[idx] = {word: word, score: score} if score > 0

  end

  return scores.compact
end

def get_words()
  puts "words?"
  words = STDIN.readline.strip.split(/\s+/)
  
  return words
end

words = get_words()
picks = {}
continue = true

while continue
  result = crack(words, picks).sort {|w1, w2| w2[:score] <=> w1[:score] }
  result.each_with_index do |res, idx|
    puts "#{idx}) #{res[:word]} - #{res[:score]}"
  end
  puts "pick?"
  pick = STDIN.readline.strip.to_i
  puts "score?"
  score = STDIN.readline.strip.to_i
  
  picks[result[pick][:word]] = score
end
