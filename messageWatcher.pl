use strict;
use warnings;
use LWP::Simple;
use HTML::TableExtract;
use Text::CSV;


#store the current year in a variable
my $currentYear = (localtime)[5] + 1900;

our $baseNavyUrl = "https://www.mynavyhr.navy.mil";
our $baseUsmcUrl = "https://www.marines.mil";

# URL to scrape
our $NavadminUrl = "$baseNavyUrl/References/Messages/NAVADMIN-$currentYear/";
our $AlNavUrl = "$baseNavyUrl/References/Messages/ALNAV-$currentYear/";
our $MaradminUrl = "$baseUsmcUrl/News/Messages/Category/14336/Year/$currentYear/";
our $AlMarUrl = "$baseUsmcUrl/News/Messages/Category/14335/Year/$currentYear/";

our $scanFrequency = 1; #in minutes
our $scanActive = 1; #1 = active, 0 = inactive

our $html_content;
our $table;

# Initialize the active message index
our $NavadminActiveIndex = 0;
our $AlNavActiveIndex = 0;
our $MaradminActiveIndex = 0;
our $AlMarActiveIndex = 0;

our $lastUpdateDate;
our $lastUpdateTime;

our @watchers = (); #Each watcher will have a name, email address, a list of subjects keywords and a list of body keywords

#load watchers from csv file
load_watchers_from_csv();

#write a sub that writes watcher data to a csv file named "watchers.csv" in the root directory
sub write_watchers_to_csv {

    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1, eol => "\n" });
    my $filename = "watchers.csv";

    open(my $fh, ">:encoding(utf8)", $filename) or die "Could not open '$filename' for writing: $!";

    # Write headers to CSV file
    $csv->print($fh, ["Name", "Email", "Phone", "Subject Keywords", "Body Keywords"]);

    # Write data to CSV file
    for (my $i = 0; $i < scalar @watchers; $i++) {
        $csv->print($fh, [$watchers[$i]->{name}, $watchers[$i]->{email}, $watchers[$i]->{subjectKeyword}, $watchers[$i]->{bodyKeyword}]);
    }

    close $fh;
}

#write a sub that reads watcher data from a csv file named "watchers.csv"
sub load_watchers_from_csv {

    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1, eol => "\n" });
    my $filename = "watchers.csv";

    unless (-e $filename) {
        warn "\e[31mFile '$filename' does not exist.\e[0m";
        return;
    }

    open(my $fh, "<:encoding(utf8)", $filename) or warn "\e[31mCould not open '$filename' for reading: $!\e[0m";

    # Read headers from CSV file
    my $headers = $csv->getline($fh);

    #clear the arrays
    @watchers = ();

    #Read data from CSV file
    while (my $row = $csv->getline($fh)) {
        my $watcher = {
            name => $row->[0],
            email => $row->[1],
            phone => $row->[2],
            subjectKeyword => $row->[3],
            bodyKeyword => $row->[4]
        };
        #Print watcher data to console
        print "-------------------------------------------------\n";
        print "Watcher Loaded:\n";
        print "Name: $watcher->{name}\n";
        print "Email: $watcher->{email}\n";
        print "Phone: $watcher->{phone}\n";
        print "Subject Keywords: $watcher->{subjectKeyword}\n";
        print "Body Keywords: $watcher->{bodyKeyword}\n";
        push @watchers, $watcher;
    }

    close $fh;

}

# Initialize arrays
our (@NavadminMessages, @NavadminSubjects, @NavadminDates, @NavadminUrls);
our (@AlNavMessages, @AlNavSubjects, @AlNavDates, @AlNavUrls);
our (@MaradminMessages, @MaradminSubjects, @MaradminDates, @MaradminUrls);
our (@AlMarMessages, @AlMarSubjects, @AlMarDates, @AlMarUrls);

do {
    scanMessages();
    print "Sleeping for $scanFrequency minute(s)\n";
    sleep $scanFrequency * 60;
} while ($scanActive == 1);


sub checkWatchers {
    my $messageNumber = shift;
    my $index = findMessageIndex($messageNumber);
    my $message = $NavadminMessages[$index];
    my $subject = $NavadminSubjects[$index];
    my $date = $NavadminDates[$index];
    my $url = $NavadminUrls[$index];
    my $body = extractTextFromUrl($url);

    print "Body: $body\n";

    # Remove any escape sequences from the message, subject, and date
    $message =~ s/\e\[\d+m//g;
    $message =~ s/á//g;
    $message =~ s/Â//g;
    $message =~ s/\s+/ /g;

    $subject =~ s/\e\[\d+m//g;
    $subject =~ s/á//g;
    $subject =~ s/Â//g;
    $subject =~ s/\s+/ /g;

    $date =~ s/\e\[\d+m//g;
    $date =~ s/á//g;
    $date =~ s/Â//g;
    $date =~ s/\s+/ /g;

    my $matched = 0;
    my $matchedWatcher;
    #Iterate through each watcher
    foreach my $watcher (@watchers) {
        #Check if the subject contains any of the watcher's subject keywords
        my $subjectKeyword = $watcher->{subjectKeyword};
        if ($subjectKeyword !~ /^\s*$/ && $subject =~ /$subjectKeyword/i) {
            $matched = 1;
            $matchedWatcher = $watcher;
        }
        #Check if the body contains the watcher's body keyword in its entirety
        my $bodyKeyword = $watcher->{bodyKeyword};
        if ($bodyKeyword !~ /^\s*$/ && $body =~ /\b$bodyKeyword\b/i) {
            $matched += 2;
            $matchedWatcher = $watcher;
        }
    }

    if ($matched) {
        my $matchedOn = "";
        if ($matched == 1) {
            $matchedOn = "Subject";
        } elsif ($matched == 2) {
            $matchedOn = "Body";
        } elsif ($matched == 3) {
            $matchedOn = "Subject and Body";
        }

        #Print Matched Message Information
        print "-------------------------------------------------\n";
        print "Watcher: " . $matchedWatcher->{name} . " matched on $matchedOn\n";
        print "Watcher Email: " . $matchedWatcher->{email} . "\n";
        print "Watcher Phone: " . $matchedWatcher->{phone} . "\n";
        print "Watcher Subject Keyword: " . $matchedWatcher->{subjectKeyword} . "\n";
        print "Watcher Body Keyword: " . $matchedWatcher->{bodyKeyword} . "\n";

                       
    }
}

#Write a sub that extracts the text from the provided url page and stores it in a variable called $body
sub extractTextFromUrl {
    my $url = shift;
    my $body = get($url);
    return $body;
}


sub scanMessages {
    print "-------------------------------------------------\n";
    # Get the HTML content of the URL
    $html_content = get($NavadminUrl);

    # Create a new HTML::TableExtract object
    my $te = HTML::TableExtract->new( headers => [qw(Message Subject Date)] );

    # Parse the HTML content and extract the table data
    $te->parse($html_content);

    # Get the first table found
    $table = $te->first_table_found;

    #clear all arrays
    @NavadminMessages = @NavadminSubjects = @NavadminDates = @NavadminUrls = ();
    @AlNavMessages = @AlNavSubjects = @AlNavDates = @AlNavUrls = ();
    @MaradminMessages = @MaradminSubjects = @MaradminDates = @MaradminUrls = ();
    @AlMarMessages = @AlMarSubjects = @AlMarDates = @AlMarUrls = ();

    #load state from csv file
    load_state_from_csv();

    #load NAVADMIN data from web
    refreshNavadminDataFromWeb();

    refreshUpdateDateTime();

    #If new index > old index: There are new messages
    my $newHighestMessageNumber = highestMessageNumber(1);
    if ($newHighestMessageNumber > $NavadminActiveIndex) {
        #print statement showing there are new messages in red
        print "\e[31mThere are new NAVADMIN messages.\e[0m\n";
        print "Old highest NAVADMIN message index: $NavadminActiveIndex\n";
        print "New highest NAVADMIN message index: $newHighestMessageNumber\n";

        #Iterate through each of the new messages and print them in green
        foreach my $message (@NavadminMessages) {
            my $currentMessageNumber = messageNumber($message);
            if ($currentMessageNumber <= $NavadminActiveIndex) {
                next;
            }

            my $index = findMessageIndex($currentMessageNumber);
            
            my $subject = $NavadminSubjects[$index];
            my $date = $NavadminDates[$index];
            my $url = $NavadminUrls[$index];

            # Remove any escape sequences from the message, subject, and date
            $message =~ s/\e\[\d+m//g;
            $message =~ s/á//g;
            $message =~ s/Â//g;
            $message =~ s/\s+/ /g;

            $subject =~ s/\e\[\d+m//g;
            $subject =~ s/á//g;
            $subject =~ s/Â//g;
            $subject =~ s/\s+/ /g;

            $date =~ s/\e\[\d+m//g;
            $date =~ s/á//g;
            $date =~ s/Â//g;
            $date =~ s/\s+/ /g;

            print "\e[32m New NAVADMIN found: $message || Subject: $subject || Date: $date || $url\e[0m\n";
            #Trigger other actions here for this new message
            checkWatchers(messageNumber($message));
        }


    } else {
        print "\e[32mThere are no new NAVADMIN messages!\e[0m\n";
        print "Old highest message index: $NavadminActiveIndex\n";
        print "New highest message index: $newHighestMessageNumber\n";
    }

    #displayNavadminMessages();

    #set the active NAVADMIN index
    $NavadminActiveIndex = highestMessageNumber(1);

    #set the active ALNAV index
    $AlNavActiveIndex = highestMessageNumber(2);

    #set the active MARADMIN index
    $MaradminActiveIndex = highestMessageNumber(3);

    #set the active ALMAR index
    $AlMarActiveIndex = highestMessageNumber(4);


    #save state to csv file
    write_state_to_csv();

    #save data to csv file
    write_to_csv();
}

sub write_to_csv {

    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1, eol => "\n" });
    my $filename = "data.csv";

    open(my $fh, ">:encoding(utf8)", $filename) or die "Could not open '$filename' for writing: $!";

    # Write headers to CSV file
    $csv->print($fh, ["Message", "Subject", "Date", "URL"]);

    # Write data to CSV file
    for (my $i = 0; $i < scalar @NavadminMessages; $i++) {
        $csv->print($fh, [$NavadminMessages[$i], $NavadminSubjects[$i], $NavadminDates[$i], $NavadminUrls[$i]]);
    }

    close $fh;
}

sub refreshNavadminDataFromCSV {

    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1, eol => "\n" });
    my $filename = "data.csv";

    unless (-e $filename) {
        warn "\e[31mFile '$filename' does not exist.\e[0m";
        return;
    }

    open(my $fh, "<:encoding(utf8)", $filename) or warn "\e[31mCould not open '$filename' for reading: $!\e[0m";

    # Read headers from CSV file
    my $headers = $csv->getline($fh);

    #clear the arrays
    @NavadminMessages = ();
    @NavadminSubjects = ();
    @NavadminDates = ();
    @NavadminUrls = ();

    # Read data from CSV file
    while (my $row = $csv->getline($fh)) {
        push @NavadminMessages, $row->[0];
        push @NavadminSubjects, $row->[1];
        push @NavadminDates, $row->[2];
        push @NavadminUrls, $row->[3];
    }

    close $fh;

}

#write a sub that writes application state data to a csv file named "state.csv" in the root directory
sub write_state_to_csv {

    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1, eol => "\n" });
    my $filename = "state.csv";

    open(my $fh, ">:encoding(utf8)", $filename) or die "Could not open '$filename' for writing: $!";

    # Write headers to CSV file
    $csv->print($fh, ["NAVADMIN Active Index", "ALNAV Active Index", "MARADMIN Active Index", "ALMAR Active Index", "Last Update Date", "Last Update Time"]);

    # Write data to CSV file
    $csv->print($fh, [$NavadminActiveIndex, $AlNavActiveIndex, $MaradminActiveIndex, $AlMarActiveIndex, $lastUpdateDate, $lastUpdateTime]);
    $csv->print($fh, []);

    close $fh;
}

#write a sub that reads application state data from a csv file named "state.csv"
sub load_state_from_csv {

    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1, eol => "\n" });
    my $filename = "state.csv";

    unless (-e $filename) {
        warn "\e[31mFile '$filename' does not exist.\e[0m";
        return;
    }

    open(my $fh, "<:encoding(utf8)", $filename) or warn "\e[31mCould not open '$filename' for reading: $!\e[0m";

    # Read headers from CSV file
    my $headers = $csv->getline($fh);

    #clear the arrays
    $NavadminActiveIndex = 0;
    $AlNavActiveIndex = 0;
    $MaradminActiveIndex = 0;
    $AlMarActiveIndex = 0;

    #Read data from CSV file
    my $row = $csv->getline($fh);
    $NavadminActiveIndex = $row->[0];
    print "NAVADMIN Active Index loaded: $NavadminActiveIndex\n";
    $AlNavActiveIndex = $row->[1];
    print "ALNAV Active Index loaded: $AlNavActiveIndex\n";
    $MaradminActiveIndex = $row->[2];
    print "MARADMIN Active Index loaded: $MaradminActiveIndex\n";
    $AlMarActiveIndex = $row->[3];
    print "ALMAR Active Index loaded: $AlMarActiveIndex\n";
    $lastUpdateDate = $row->[4];
    print "Last Update Date loaded: $lastUpdateDate\n";
    $lastUpdateTime = $row->[5];
    print "Last Update Time loaded: $lastUpdateTime\n";
    

    close $fh;

}

#Extract the number before the forward slash in this example "252/23"
sub messageNumber {

    my $navadminNumber = shift;
    my $index = index($navadminNumber, "/");
    $navadminNumber = substr($navadminNumber, 0, $index);

    return $navadminNumber;
}

sub refreshUpdateDateTime {

    #set the current system date in the format "MM/DD/YYYY"
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $lastUpdateDate = sprintf("%02d/%02d/%04d", $mon+1, $mday, $year+1900);
    #print "Last Update Date: $lastUpdateDate\n";

    #set the current system time in the format "HH:MM:SS"
    $lastUpdateTime = sprintf("%02d:%02d:%02d", $hour, $min, $sec);
    #print "Last Update Time: $lastUpdateTime\n";

}

#Write a sub that retrieves the highest message number from the array in the messageNumber() format
sub highestMessageNumber {
    # 1 = NAVADMIN, 2 = ALNAV, 3 = MARADMIN, 4 = ALMAR
    my $messageType = shift;
    my $highestMessageNumber = 0;

    if ($messageType == 1) {
        foreach my $message (@NavadminMessages) {

            my $navadminNumber = messageNumber($message);

            if ($navadminNumber > $highestMessageNumber) {
                $highestMessageNumber = $navadminNumber;
            }
        }

        return $highestMessageNumber;
    } elsif ($messageType == 2) {
        foreach my $message (@AlNavMessages) {

            my $alnavNumber = messageNumber($message);

            if ($alnavNumber > $highestMessageNumber) {
                $highestMessageNumber = $alnavNumber;
            }
        }

        return $highestMessageNumber;
    } elsif ($messageType == 3) {
        foreach my $message (@MaradminMessages) {

            my $maradminNumber = messageNumber($message);

            if ($maradminNumber > $highestMessageNumber) {
                $highestMessageNumber = $maradminNumber;
            }
        }

        return $highestMessageNumber;
    } elsif ($messageType == 4) {
        foreach my $message (@AlMarMessages) {

            my $almarNumber = messageNumber($message);

            if ($almarNumber > $highestMessageNumber) {
                $highestMessageNumber = $almarNumber;
            }
        }

        return $highestMessageNumber;
    } else {
        print "Invalid message type\n";
    }
    

    
}

sub refreshNavadminDataFromWeb {
    # Remove any instances of "á" in the table
    $table =~ s/á//g;

    # Ensure there are no more than 1 space between words
    $table =~ s/\s+/ /g;

    #Remove any new lines in the table
    $table =~ s/\n//g;

    #Clear the arrays
    @NavadminMessages = ();
    @NavadminSubjects = ();
    @NavadminDates = ();
    @NavadminUrls = ();

    # Loop through each row of the table and store the data in the arrays
    foreach my $row ($table->rows) {
        push @NavadminMessages, $row->[0];
        push @NavadminSubjects, $row->[1];
        push @NavadminDates, $row->[2];
    }
    # Extract all hrefs that include "/Portals/55/Messages/NAVADMIN/NAV$currentYear" in the URL
    @NavadminUrls = $html_content =~ /href="(.*?\/Portals\/55\/Messages\/NAVADMIN\/NAV$currentYear.*?)"/g;
    #append each @url value with $baseNavyUrl
    foreach my $NavadminUrl (@NavadminUrls) {
        $NavadminUrl = $baseNavyUrl . $NavadminUrl;
    }

    #Reverse the order of the arrays
    @NavadminMessages = reverse @NavadminMessages;
    @NavadminSubjects = reverse @NavadminSubjects;
    @NavadminDates = reverse @NavadminDates;
    @NavadminUrls = reverse @NavadminUrls;

    #Print a debug statement showing the number of messages found
    print "Found " . scalar @NavadminMessages . " total NAVADMIN messages\n";

    #print a debug statement showing the number of urls found
    #print "Found " . scalar @NavadminUrls . " urls\n";
}

#Write a sub that is provided the message number and returns the index of the array that contains the message
sub findMessageIndex {
    my $messageNumber = shift;
    my $index = 0;

    foreach my $message (@NavadminMessages) {
        if (messageNumber($message) == $messageNumber) {
            return $index;
        }
        $index++;
    }

    return -1;
}

sub displayNavadminMessages {
    my $index = 0;
    foreach my $message (@NavadminMessages) {

        # Remove any instances of "á" in the table
        $NavadminMessages[$index] =~ s/á//g;
        $NavadminSubjects[$index] =~ s/á//g;
        $NavadminDates[$index] =~ s/á//g;

        # Ensure there are no more than 1 space between words
        $NavadminMessages[$index] =~ s/\s+/ /g;
        $NavadminSubjects[$index] =~ s/\s+/ /g;
        $NavadminDates[$index] =~ s/\s+/ /g;

        #Remove any new lines in the table
        $NavadminMessages[$index] =~ s/\n//g;
        $NavadminSubjects[$index] =~ s/\n//g;
        $NavadminDates[$index] =~ s/\n//g;

        print $index + 1 . ") Message: $message || " . "Subject: " . $NavadminSubjects[$index] . " || Date: " . $NavadminDates[$index] . " || " . $NavadminUrls[$index] . "\n";
        $index++;
    }
}

END {
  # perform any necessary cleanup
  write_watchers_to_csv();
}