require 'rubygems'
require 'minitest/autorun'
require 'yaml'

$:.unshift File.expand_path('../../lib', __FILE__)
require 'romniture'

class DWResponseTest < Minitest::Test

  def setup
    #do nothing 
    puts "setting up!"
  end
  
  def test_good
    test_dataset = [
      {
        desc: "Baseline test",
        chunks: ["Column A,Column B,Column C\n1A,1B,1C\n2A,2B,2C"],
        expected: [
          {"Column A" => "1A", "Column B" => "1B", "Column C" => "1C"},
          {"Column A" => "2A", "Column B" => "2B", "Column C" => "2C"}
        ]
      },
      {
        desc: "Garbage header test",
        chunks: ["\xEF\xBB\xBFColumn A,Column B,Column C\n1A,1B,1C\n2A,2B,2C"],
        expected: [
          {"Column A" => "1A", "Column B" => "1B", "Column C" => "1C"},
          {"Column A" => "2A", "Column B" => "2B", "Column C" => "2C"}
        ]
      },
      {
        desc: "Chunked test",
        chunks: ["Column"," A,Column B,","Column C","\n1A,1B",",","1C\n2A,2B",",2C"],
        expected: [
          {"Column A" => "1A", "Column B" => "1B", "Column C" => "1C"},
          {"Column A" => "2A", "Column B" => "2B", "Column C" => "2C"}
        ]
      },
      {
        desc: "Unchunked test with enclosed linebreaks",
        chunks: ["Column A,Column B,Column C\n\"1A\nc\",1B,1C\n2A,2B,2C"],
        expected: [
          {"Column A" => "1A\nc", "Column B" => "1B", "Column C" => "1C"},
          {"Column A" => "2A", "Column B" => "2B", "Column C" => "2C"}
        ]
      },
      {
        desc: "Chunked test with enclosed linebreaks",
        chunks: ["Column A,","Column B,Column"," C\n","\"1A\nc","\",1B",",1C\n2A,2B,2C"],
        expected: [
          {"Column A" => "1A\nc", "Column B" => "1B", "Column C" => "1C"},
          {"Column A" => "2A", "Column B" => "2B", "Column C" => "2C"}
        ]
      }
    ]

    modulos = [1,5,10]
    modulos.each do |modulo|
      test_dataset.each do |test_data|
        puts "[testdata]#{test_data}[/testdata]"

        myrecords = []

        mapper = lambda do |records|
          records.each do |record|
            myrecords.push(record.to_hash)
          end
        end
        
        response = ROmniture::DWResponse.new(nil, mapper)
        response.process_chunks(test_data[:chunks],modulo)

        assert_equal(myrecords,test_data[:expected])
      end
    end
  end

end