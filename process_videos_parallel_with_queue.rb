require_relative './person_tracking_service'

tracking_service = PersonTrackingSerivce.new

`aws s3 sync --exclude "*" --include "*.jpg" safe_faces_to_collection/ s3://video-aws/`
Dir['safe_faces_to_collection/**/*.jpg'].each do |snapshot_with_face|
  puts "Add faces to collection from #{snapshot_with_face}"
  tracking_service.addFaceToCollection(snapshot_with_face)
end

puts 'Uploading new video:'

`find new -name '*.avi' | xargs -I % ffmpeg -i "%" -an -vcodec copy "%.mov"`
`find new -name '*.avi' | xargs -I % rm "%"`
`aws s3 sync --exclude "*" --include "*.mov" new/ s3://video-aws/`

puts 'Done'

require 'concurrent'
pool = Concurrent::FixedThreadPool.new(15)

video_to_process = Dir['new/**/*.mov']

video_to_process.each do |video|
  pool.post do
    worker_tracking_service = PersonTrackingSerivce.new

    persons = worker_tracking_service.find_new_persons_in(video)

    next if persons.empty?

    persons.each do |person|
      worker_tracking_service.snapshot_face_for(person, video)
    end
  end
end

# tell the pool to shutdown in an orderly fashion, allowing in progress work to complete
pool.shutdown
# now wait for all work to complete, wait as long as it takes
pool.wait_for_termination
