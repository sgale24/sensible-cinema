#
# warning: somewhat scary/explicit!

# see subtitle_todo file










































profanities = {'hell' => 'heck', 'g' + 
'o' + 'd' => 'g..', 'lord' => 'lo..', 'da' + 
'mn' => 'da..', 'f' + 
 117.chr +
99.chr + 
 107.chr => 
'f...',
'bi' +
'tc' + 104.chr => 'b.....',
'bas' +
'tard' => 'ba.....',
('a'
 + 's'*2) => 'a..'
}

incoming = File.read(ARGV[0])

for profanity, sanitized in profanities
  # dunno if we should force words to just start with this or contain it anywhere...
  # what about 'godly' for example?
  # or 'ungodly' ?
  if incoming =~ Regexp.new(profanity, Regexp::IGNORECASE)
    p 'contains', sanitized
  end
end












