# encoding: utf-8
require 'foodcritic'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

desc 'Run Foodcritic lint checks'
FoodCritic::Rake::LintTask.new(:lint) do |t|
  t.options = { fail_tags: ['any'] }
end

desc 'Run rubocop tests'
RuboCop::RakeTask.new(:rubocop) do |t|
  t.options = ['-D']
end

desc 'Run all tests'
task test: [:rubocop, :lint]
task default: :test
