omniture_client
===============

This is a private fork of "[ROmniture](https://github.com/RobGoretsky/ROmniture)".

Original ROmniture readme
-------------------------

## Overview
romniture is a minimal Ruby wrapper to [Omniture's REST API](http://developer.omniture.com).  It follows a design policy similar to that of [sucker](https://rubygems.org/gems/sucker) built for Amazon's API.

Omniture's API is closed, you have to be a paying customer in order to access the data.

## Installation
    [sudo] gem install romniture

## Initialization and authentication
romniture requires you supply the `username`, `shared_secret` and `environment` which you can access within the Company > Web Services section of the Admin Console.  The environment you'll use to connect to Omniture's API depends on which data center they're using to store your traffic data and will be one of:

* San Jose (https://api.omniture.com/admin/1.3/rest/)
* Dallas (https://api2.omniture.com/admin/1.3/rest/)
* London (https://api3.omniture.com/admin/1.3/rest/)
* San Jose Beta (https://beta-api.omniture.com/admin/1.3/rest/)
* Dallas (beta) (https://beta-api2.omniture.com/admin/1.3/rest/)
* Sandbox (https://api-sbx1.omniture.com/admin/1.3/rest/)

Here's an example of initializing with a few configuration options.

    client = ROmniture::Client.new(
      username, 
      shared_secret, 
      :san_jose, 
      :verify_mode  => nil  # Optionaly change the ssl verify mode.
      :log => false,        # Optionally turn off logging if it ticks you off
      :wait_time => 1       # Amount of seconds to wait in between pinging 
                            # Omniture's servers to see if a report is done processing (BEWARE OF TOKENS!)
      )
    
## Usage
There are three methods:

* `get_report` - used to...while get reports and
* `request` - more generic used to make any kind of request
* `get_dw_result` - downloads the file URL returned by the Data Warehouse request

Refer to [Omniture's Developer Portal](http://developer.omniture.com) when writing API calls.

The response returned by either of these requests Ruby (parsed JSON).

## Examples
    # Find all the company report suites
    client.request('Company.GetReportSuites')
    
    # Get an overtime report
    client.get_report "Report.QueueOvertime", {
      "reportDescription" => {
        "reportSuiteID" => "#{@config["report_suite_id"]}",
        "dateFrom" => "2011-01-01",
        "dateTo" => "2011-01-10",
        "metrics" => [{"id" => "pageviews"}]
        }
      }

    # Create a Data Warehouse request
    parameters = {
      "rsid"=>rsid,
      'Breakdown_List' => ['visitor_id'],
      "Contact_Name"=>"your name",
      "Contact_Phone"=>"your phone number",
      'Date_From' => '10/30/14',
      'Date_Granularity' => 'day',
      'Date_Preset' => '',
      'Date_To' => '11/04/14',
      'Date_Type' => 'range',
      'Email_Subject' => 'DW API test (subject) Did not use ftp host',
      'Email_To' => 'you@email.net', 
      'FTP_Dir' => '',
      'FTP_Host' => 'send_via_api',
      'FTP_Password' => '',
      'FTP_Port' => '22',
      'FTP_UserName' => '',
      'File_Name' => 'filename',
      'Metric_List' => ['revenue','event4','event5','event6','event7','event8'],
      'Report_Description' => 'DW API test (description)',
      'Report_Name' => 'DW API test (name)',
      'Segment_Id' => segmentId
    }

    requestId = @client.request('DataWarehouse.Request', parameters)

    # Check on a Data Warehouse request (note, this should be done until status shows the request has been completed)
    response = client.request('DataWarehouse.CheckRequest',{'Request_Id'=>requestId})

    # Download the returned Data Warehouse URL
    client.get_dw_result(response['data_url'])


## Testing

In order to run the tests, you must copy `test/example_config.yml` to `test/config.yml` and fill in credentials and necessary values.

    # Run all tests using Rake

    rake test

    # Test the client

    ruby test/client_test.rb

    # Test the VisitorId class

    ruby test/visitorid_test.rb
