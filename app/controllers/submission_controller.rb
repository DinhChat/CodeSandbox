# frozen_string_literal: true

class SubmissionController < ApplicationController
  # POST /submissions/run
  def run
    submission_code = params[:submission_code]
    language = params[:language]
    test_cases = params[:test_cases]
    time_limit = (params[:time_limit] || 2).to_i
    memory_limit = (params[:memory_limit] || 256).to_i

    if submission_code.blank? || language.blank? || test_cases.blank?
      render json: { error: "Missing required parameters" }, status: :bad_request
      return
    end

    results = []
    test_cases.each_with_index do |test_case, index|
      Rails.logger.info "Running test case #{index + 1} for language #{language}"
      result = run_code_in_docker(submission_code, language, test_case[:input], time_limit, memory_limit)

      # So sánh output và đánh giá kết quả
      passed = (result[:output].strip == test_case[:expected_output].strip)

      results << {
        test_case_number: index + 1,
        input: test_case[:input],
        expected_output: test_case[:expected_output],
        actual_output: result[:output],
        time_taken: result[:time],
        memory_used: result[:memory],
        status: result[:status], # e.g., "Success", "Time Limit Exceeded", "Memory Limit Exceeded", "Runtime Error"
        passed: passed
      }
    end

    render json: { results: results }, status: :ok
  rescue StandardError => e
    Rails.logger.error "Error processing submission: #{e.message}\n#{e.backtrace.join("\n")}"
    render json: { error: "Internal server error", message: e.message }, status: :internal_server_error
  end

  private
  def run_code_in_docker(code, language, input_data, time_limit, memory_limit)
    submission_id = SecureRandom.uuid
    temp_dir = "/tmp/#{submission_id}"
    code_file_name = get_code_file_name(language)
    executable_file_name = get_executable_file_name(language)
    docker_image = get_docker_image(language)

    # 1. Chuẩn bị file code và input
    FileUtils.mkdir_p(temp_dir) unless File.directory?(temp_dir)
    File.write("#{temp_dir}/#{code_file_name}", code)
    File.write("#{temp_dir}/input.txt", input_data)

    # 2. Xây dựng Docker command
    # -i: Interactive
    # -t: Pseudo-TTY
    # --rm: Remove container after exit
    # -v: Mount volume (current temp_dir to /app inside container)
    # --network none: Disable network access for security
    # --memory #{memory_limit}m: Set memory limit
    # --cpu-quota=100000 --cpu-period=100000: Limit to 1 CPU core (or less) if needed
    # --cap-drop=ALL: Drop all capabilities for security
    # --security-opt="no-new-privileges": Prevent privilege escalation
    # --pids-limit 64: Limit number of processes
    # --ulimit nproc=64: Limit number of processes (Linux specific)
    # --ulimit nofile=1024: Limit number of open files

    # Script để chạy bên trong container
    # Compile and run script will be mounted into the container.
    # We'll create a generic `run_script.sh` that handles compilation/execution based on language.

    script_content = generate_run_script(language, code_file_name, executable_file_name)
    File.write("#{temp_dir}/run_script.sh", script_content)
    FileUtils.chmod(0755, "#{temp_dir}/run_script.sh") # Make script executable

    docker_command = [
      "docker run",
      "-i --rm",
      "--network none",
      "--memory #{memory_limit}m",
      "--pids-limit 64", # Limit processes
      "--ulimit nproc=64:64", # soft:hard limit
      "--ulimit nofile=1024:1024", # soft:hard limit
      "--cpus=\"1.0\"", # Limit to 1 CPU core, adjust as needed
      "-v #{temp_dir}:/app", # Mount our temp directory
      docker_image,
      "timeout #{time_limit}s /app/run_script.sh" # Execute our script inside container with timeout
    ].join(" ")

    Rails.logger.info "Executing Docker command: #{docker_command}"

    # 3. Thực thi Docker command
    # open3 allows running commands and capturing stdout, stderr, and waiting for exit status.
    stdout_str, stderr_str, status = Open3.capture3(docker_command)

    # 4. Phân tích kết quả
    output = ""
    error = ""
    time_taken = 0.0
    memory_used = 0 # MB
    status_text = "Runtime Error" # Default error status

    if status.success?
      # We need to parse output and metrics from stdout_str/stderr_str
      # Our run_script.sh will output results in a specific format

      # Example parsing (this needs to match what run_script.sh outputs)
      lines = stdout_str.split("\n")
      output_lines = []
      metrics_line = nil
      lines.each do |line|
        if line.start_with?("JUDGE_METRICS:")
          metrics_line = line
        else
          output_lines << line
        end
      end

      output = output_lines.join("\n").strip

      if metrics_line
        metrics = JSON.parse(metrics_line.sub("JUDGE_METRICS:", ""))
        time_taken = metrics["time"] || 0.0
        memory_used = metrics["memory"] || 0
      end

      status_text = "Success"

    elsif status.exitstatus == 124 # Timeout command's exit code for TLE
      status_text = "Time Limit Exceeded"
    elsif stderr_str.include?("Memory limit exceeded") # Heuristic for MLE, might need refinement
      status_text = "Memory Limit Exceeded"
    else
      status_text = "Runtime Error" # Catch all for other errors
    end

    # Clean up temporary directory
    FileUtils.remove_entry_point(temp_dir)

    {
      output: output,
      time: time_taken,
      memory: memory_used,
      status: status_text,
      error_message: stderr_str # Keep stderr for debugging
    }
  rescue => e
    Rails.logger.error "Error in run_code_in_docker: #{e.message}\n#{e.backtrace.join("\n")}"
    # Clean up temporary directory in case of error
    FileUtils.remove_entry_point(temp_dir) if File.directory?(temp_dir)
    {
      output: "",
      time: 0.0,
      memory: 0,
      status: "Internal Error",
      error_message: e.message
    }
  end

  def get_code_file_name(language)
    case language
    when 'python' then 'solution.py'
    when 'java' then 'Solution.java' # Class name must be Solution
    when 'cpp' then 'solution.cpp'
    when 'ruby' then 'solution.rb'
    # Add other languages
    else 'solution.txt'
    end
  end

  def get_executable_file_name(language)
    case language
    when 'java' then 'Solution' # Class name
    when 'cpp' then 'a.out'
    # For interpreted languages, the code file itself is the executable
    else get_code_file_name(language)
    end
  end

  def get_docker_image(language)
    case language
    when 'python' then 'python:3.9-slim-buster'
    when 'java' then 'openjdk:11-jre-slim-buster' # Use JRE for running, JDK for compiling
    when 'cpp' then 'gcc:9-slim' # Or a more lightweight C++ image like alpine/gcc
    when 'ruby' then 'ruby:3.0-slim-buster'
    # You might want to build custom images with specific versions or tools
    else 'alpine/base' # Fallback
    end
  end

  # This script runs inside the Docker container
  # It needs to handle compilation (if any) and execution,
  # and print metrics in a structured way (e.g., JSON)
  def generate_run_script(language, code_file_name, executable_file_name)
    script = String.new
    script << "#!/bin/bash\n"
    script << "cd /app\n"
    script << "start_time=$(date +%s.%N)\n"
    script << "max_memory_usage=0\n"

    case language
    when 'python'
      script << "python #{code_file_name} < input.txt\n"
    when 'java'
      script << "javac #{code_file_name} 2> compile_error.txt\n"
      script << "if [ $? -ne 0 ]; then cat compile_error.txt; exit 1; fi\n"
      script << "java #{executable_file_name} < input.txt\n"
    when 'cpp'
      script << "g++ #{code_file_name} -o #{executable_file_name} 2> compile_error.txt\n"
      script << "if [ $? -ne 0 ]; then cat compile_error.txt; exit 1; fi\n"
      script << "./#{executable_file_name} < input.txt\n"
    when 'ruby'
      script << "ruby #{code_file_name} < input.txt\n"
    else
      script << "echo \"Unsupported language: #{language}\"\n"
      script << "exit 1\n"
    end

    script << "end_time=$(date +%s.%N)\n"
    script << "time_taken=$(echo \"$end_time - $start_time\" | bc -l)\n"

    # Get memory usage (this is tricky in Docker and often needs privileged access or cgroups)
    # For a simplified approach, you might rely on Docker's --memory flag for limits
    # and not try to precisely measure *within* the container without more advanced tools.
    # A more robust solution might involve `cgget` or similar tools, which are complex to set up.
    # For now, we'll assume Docker's --memory limit is sufficient for judging MLE,
    # or you might use `/usr/bin/time -v` if available and not too slow.
    # For simplicity, we'll just report time.

    # If you want to get memory usage reliably, you often need to run a separate process
    # outside the container that monitors the container's cgroup metrics.
    # For this example, we'll just report a dummy memory.
    script << "echo \"JUDGE_METRICS: {\\\"time\\\": $time_taken, \\\"memory\\\": 0}\"\n" # Dummy memory for now
    script
  end
end
