require 'fileutils'

FileUtils.rm_rf("aries")
for i in 1..100
  puts "Generating house #{i}..."

  # Generate OSM
  command = "~/OpenStudio-3.3.0+ad235ff36e-Ubuntu-20.04/usr/local/openstudio-3.3.0/bin/openstudio workflow/run_simulation.rb -x aries.xml -o aries --add-detailed-schedule stochastic --random-seed #{i} --debug"
  `#{command}`
  
  i3 = i.to_s.rjust(3, "0")
  
  # Copy OSM to output location
  FileUtils.cp("aries/run/in.osm",
               "aries/house#{i3}.osm")
  
  # Copy schedule CSV to output location
  schedule_csv = Dir["files/*.csv"][0]
  FileUtils.cp(schedule_csv,
               "aries/house#{i3}.csv")
  
  # Rename schedule CSV in OSM
  osm_data = File.read("aries/house#{i3}.osm")
  File.write("aries/house#{i3}.osm", osm_data.gsub(File.basename(schedule_csv), "house#{i3}.csv"))
  
  # Cleanup
  FileUtils.rm_rf("files")
  FileUtils.rm_rf("aries/run")
end
puts "Done. Output files created at aries/"