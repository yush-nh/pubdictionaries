Delayed::Worker.max_attempts = 1
Delayed::Worker.max_run_time = 7.days
Delayed::Worker.logger = Logger.new(File.join(Rails.root, 'log', 'delayed_job.log'))
