Given /^the process is not running$/ do
  running = `ps auwx | grep emissary | grep -v grep | grep -vi vim`
  running.chomp.should == ''
end

When /^I call '(.+)'$/ do |cmd|
  @resp = `#{cmd} 2>&1`
end

Then /^the help page should be displayed$/ do
  @resp.should match(/Synopsis/)
end
