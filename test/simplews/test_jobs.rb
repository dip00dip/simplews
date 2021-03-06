require File.dirname(File.dirname(__FILE__)) + '/test_helper.rb'
require 'rbbt-util'

class TestJobs < Test::Unit::TestCase
  class TestJWS < SimpleWS::Jobs

    desc "Long process"
    task :process, [], {}, ['test.txt'] do
      begin
        info(:steps => 3)
        write('test.txt', job_name)
        step(:init)
        sleep 1
        step(:step1, "Step1")
        sleep 1
        step(:step2, "Step2")
        sleep 1
        step(:step3, "Step3")
        sleep 2
      rescue
        error($!.message)
      end
    end

    Scheduler.queue_size 2
  end

  def test_descriptions
    @server = TestJWS.new("TestJWS", "Asynchronous Job Server", 'localhost', port, "tmp-TestJWS")

    Thread.new do
      @server.start
    end

    driver = SimpleWS.get_driver('http://localhost:' + port, 'TestJWS')
    assert_match /Return the WSDL/, driver.wsdl
    assert_match /Long process/, driver.wsdl
    assert_match /Job identifier/, driver.wsdl

    @server.shutdown
  end


  def test_client
    require 'soap/wsdlDriver'

    @server = TestJWS.new("TestJWS", "Asynchronous Job Server", 'localhost', port, "tmp-TestJWS")

    Thread.new do
      @server.start
    end

    driver = SimpleWS.get_driver('http://localhost:' + port, 'TestJWS')

    driver.wsdl
    
    name = driver.process("test2")

    puts "Job name #{ name }"

    assert( ! String === driver.done(name) )
    while !driver.done(name)
      puts "status: " + driver.status(name)
      sleep 1
    end


    assert_equal(3, YAML.load(driver.info(name))[:steps])
    assert(!driver.error(name))
    assert(driver.messages(name).include? "Step3")
    assert(driver.results(name).length == 1)
    result = driver.results(name).first
    assert_match(name, Base64.decode64(driver.result(result)))

    name = driver.process("test-abort")
    sleep 2
    puts "status: " + driver.status(name)
    driver.abort(name)
    sleep 2
    puts driver.status(name)
    puts driver.messages(name)
    assert(driver.aborted(name))

    FileUtils.cp "tmp-TestJWS/.save/#{name}.marshal", "tmp-TestJWS/.save/copy.marshal"
    assert(driver.aborted("copy"))
    
    # Test queue
    threads = []
    10.times {
      threads << Thread.new{
        test_name = driver.process("test-queue")
        puts "Starting #{ test_name }"
        while !driver.done(test_name)
          puts "#{ test_name }: " + driver.status(test_name)
          sleep 2
        end
      }
    }

    puts "Threads " +  threads.length.to_s
    threads.each{|t| t.join}
    sleep 10

    @server.shutdown
    sleep 3

  end

end
