use strict;
use warnings;
use LWP::Simple;
use HTML::TableExtract;
use Text::CSV;
use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::SMTP;
use Email::MIME;
use Term::ReadKey;
use SMS::Send;

#store the current year in a variable
my $currentYear = (localtime)[5] + 1900;

our $baseNavyUrl = "https://www.mynavyhr.navy.mil";
our $baseUsmcUrl = "https://www.marines.mil";

# URL to scrape
our $NavadminUrl = "$baseNavyUrl/References/Messages/NAVADMIN-$currentYear/";
our $AlNavUrl = "$baseNavyUrl/References/Messages/ALNAV-$currentYear/";
our $MaradminUrl = "$baseUsmcUrl/News/Messages/Category/14336/Year/$currentYear/";
our $AlMarUrl = "$baseUsmcUrl/News/Messages/Category/14335/Year/$currentYear/";

our $scanFrequency = 10; #in minutes
our $scanActive = 1; #1 = active, 0 = inactive

# Initialize the active message index
our $NavadminActiveIndex = 0;
our $AlNavActiveIndex = 0;
our $MaradminActiveIndex = 0;
our $AlMarActiveIndex = 0;

our $lastUpdateDate;
our $lastUpdateTime;
our $initialLoad = 1;

our $emailUsername;
our $emailPassword;
our $smsUsername;
our $smsPassword;

our @watchers = (); #Each watcher will have a name, email address, a list of subjects keywords and a list of body keywords

#load watchers from csv file
load_watchers_from_csv();

#load email credentials from csv file
load_credentials_from_csv();

# Initialize arrays
our (@NavadminMessages, @NavadminSubjects, @NavadminDates, @NavadminUrls);
our (@AlNavMessages, @AlNavSubjects, @AlNavDates, @AlNavUrls);
our (@MaradminMessages, @MaradminSubjects, @MaradminDates, @MaradminUrls);
our (@AlMarMessages, @AlMarSubjects, @AlMarDates, @AlMarUrls);


$scanActive = 1;
initiateScan();

while (1) {
    display_menu();
    print "Enter command: ";
    writeLog("Enter command: ");
    my $input = <>;
    chomp $input;
    $input = lc $input; # convert input to lowercase
    writeLog("Command Recieved: $input");
    if ($input eq 'exit') {
        last;
    } elsif ($input eq 'scan') {
        initiateScan();
    } elsif ($input =~ /^test email (\S+@\S+)$/) {
        my $email = $1;
        testEmail($email);
    } elsif ($input =~ /^test sms (\S+)$/i) {
        my $sms = $1;
        testSMS($sms);
    } elsif ($input eq 'scanactive on') {
        $scanActive = 1;
        initiateScan();
    } elsif ($input eq 'start') {
        $scanActive = 1;
        initiateScan();
    } elsif ($input eq 'scanactive off') {
        $scanActive = 0;
    }
}

sub display_menu {
    print "-------------------------------------------------\n";
    print "Command Menu:\n";
    print "1) Type 'exit' to close the program.\n";
    print "2) Type 'scan' to initiate scan.\n";
    print "3) Type 'test email [email]' to send a test email. Example: " . 'test email test@aol.com' . "\n";
    print "4) Type 'test sms [phone]' to send a test sms. Example: " . 'test sms 1234567890' . "\n";
    print "5) Type 'scanactive on/off' to turn active scanning on/off.\n";
    print "-------------------------------------------------\n";
    
    writeLog("-------------------------------------------------");
    writeLog("Command Menu:");
    writeLog("1) Type 'exit' to close the program.");
    writeLog("2) Type 'scan' to initiate scan.");
    writeLog("3) Type 'test email [email]' to send a test email. Example: " . 'test email test@aol.com' . "\n");
    writeLog("4) Type 'scanactive on/off' to turn active scanning on/off.");
    writeLog("-------------------------------------------------");
}

sub testEmail {
    my $to = shift;
    my $bcc = '';
    my $from = 'noreply@navadminwatcher.com';
    my $subject = "[TEST] New NAVADMIN Message Found";
    my $message = "This is a test email from the NAVADMIN Watcher application.  If you received this email, it means email notifications are working properly.";


    my $msg = Email::Simple->create(
        #authenticate the smtp server with the username and password

        header => [
            From    => $from,
            To      => $to,
            Bcc       => $bcc,
            Subject  => $subject,
        ],
        body => $message,
    );

    my $transport = Email::Sender::Transport::SMTP->new({
        host => 'smtp.elasticemail.com',
        port => 2525,
        sasl_username => $emailUsername,
        sasl_password => $emailPassword,
    });


    #print debug statement showing the email message
    print "-------------------------------------------------\n";
    print "Email Message:\n";
    print "From: $from\n";
    print "To: $to\n";
    print "Bcc: $bcc\n";
    print "Subject: $subject\n";
    print "-------------------------------------------------\n";

    writeLog("-------------------------------------------------");
    writeLog("Email Message:");
    writeLog("From: $from");
    writeLog("To: $to");
    writeLog("Bcc: $bcc");
    writeLog("Subject: $subject");
    writeLog("-------------------------------------------------");


    sendmail($msg, { transport => $transport });
    print "Email Sent Successfully\n";
    writeLog("Email Sent Successfully");

}

#Sub to check if the log file is more than 1MB in size.  If it is, rename it to log.txt.old (with incrementing numbers on the end of the file name) and create a new log.txt file. Use a subdirectory called logs to store the log files. If the subdirectory doesnt exist, create it.
sub checkLogFileSize {
    my $logFile = "log.txt";
    my $logDirectory = "logs";
    my $logFilePath = $logDirectory . '/' . $logFile;
    # 1 MB max size
    my $logFileMaxSize = 1000000;
    my $logFileMaxSizeMB = $logFileMaxSize / 1000000; #1MB
    
    #check if the logs directory exists
    if (-d $logDirectory) {
        #check if the log file exists
        if (-e $logFilePath) {
            #check if the log file is larger than 1MB
            my $currentLogFileSize = -s $logFilePath;
            my $currentLogFileSizeMB = sprintf("%.2f", $currentLogFileSize / 1000000);
            if ($currentLogFileSize > $logFileMaxSize) {
                writeLog("Log file ($logFile, Size: $currentLogFileSizeMB MB) is larger than $logFileMaxSizeMB MB. Archiving log file...");
                # Define the base name for the old log files
                my $baseOldLogFileName = "logs/log_old";
                my $i = 0;

                # Construct the new log file name
                my $newLogFileName = $baseOldLogFileName . ($i > 0 ? $i : "");

                # Check if a file with the new name already exists
                while (-e $newLogFileName . ".txt") {
                    $i++;
                    $newLogFileName = $baseOldLogFileName . $i;
                }

                # Rename the current log file
                rename "logs/log.txt", $newLogFileName . ".txt";
                print "Log file renamed to $newLogFileName.txt\n";

                # Create a new log file in the logs subdirectory
                my $newLogFile = "logs/log.txt";
                open(my $fh, '>', $newLogFile) or die "Could not open file '$newLogFile' $!";
                close $fh;
                print "New log file $newLogFile created\n";
            } else {
                writeLog("Log file ($logFile, Size: $currentLogFileSizeMB MB) is smaller than $logFileMaxSizeMB MB. No action required.");
                print "Log file ($logFile, Size: $currentLogFileSizeMB MB) is smaller than $logFileMaxSizeMB MB. No action required.\n";
            }
        } else {
            #create a new log file
            open(my $fh, '>', $logFilePath) or die "Could not open file '$logFile' $!";
            close $fh;
            writeLog("Log file $logFile created");
            print "Log file $logFile created\n";
        }
    } else {
        #create the logs directory
        mkdir $logDirectory;
        writeLog("Logs directory $logDirectory created");
        print "Logs directory $logDirectory created\n";
        # create a new log file in the new directory
        open(my $fh, '>', $logFilePath) or die "Could not open file '$logFilePath' $!";
        close $fh;
        writeLog("Log file $logFilePath created in new logs directory");
        print "Log file $logFilePath created in new logs directory\n";
    }
}

sub testSMS {
    my $to = shift;
    my $message = "This is a test SMS message from the NAVADMIN Watcher application.  If you received this SMS, it means SMS notifications are working properly.";

    # Create an object. There are three required values:
    my $sender = SMS::Send->new('Twilio',
    _accountsid => $smsUsername,
    _authtoken  => $smsPassword,
    _from       => '+18339393114',
    );
    
    # Send a message to me
    my $sent = $sender->send_sms(
        text => $message,
        to => $to,
    );
    
    if ($sent) {
        print "SMS Sent Successfully\n";
        writeLog("SMS Sent Successfully");
    } else {
        print "SMS Failed to Send\n";
        writeLog("SMS Failed to Send");
    }
    
}

#write a sub that converts minutes into days, hours, and minutes
sub convertMinutes {
    my $minutes = shift;
    my $days = int($minutes / 1440);
    my $hours = int(($minutes - ($days * 1440)) / 60);
    my $remainingMinutes = $minutes - ($days * 1440) - ($hours * 60);
    return "$days days, $hours hours, $remainingMinutes minutes";
}

sub initiateScan {
    my $scanCount = 0;
    my $runTime = 0;
    do {
        if (not $initialLoad) {
            #load watchers from csv file
            load_watchers_from_csv();
        }
        
        #Scan for new messages
        scanMessages();
        $scanCount++;
        if ($scanActive) {
            if ($scanCount == 1) {
                $runTime = 0;
            } elsif ($scanCount > 1) {
                $runTime = ($scanCount - 1) * $scanFrequency;
            }
            $runTime = convertMinutes($runTime);
            print "Scan Count: $scanCount, Aproximate Run Time: $runTime minutes\n";
            print "Sleeping for $scanFrequency minute(s)\n";

            writeLog("Scan Count: $scanCount, Aproximate Run Time: $runTime minutes");
            writeLog("Sleeping for $scanFrequency minute(s)");
            sleep $scanFrequency * 60;
        }
        $initialLoad = 0;
    } while ($scanActive == 1);
}

#write a sub that writes watcher data to a csv file named "watchers.csv" in the root directory
sub write_watchers_to_csv {
    writeLog("Writing watchers to csv file...");
    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1, eol => "\n" });
    my $filename = "watchers.csv";

    open(my $fh, ">:encoding(utf8)", $filename) or die "Could not open '$filename' for writing: $!";

    # Write headers to CSV file
    $csv->print($fh, ["Name", "Email", "Phone", "Subject Keywords", "Body Keywords"]);

    # Write data to CSV file
    foreach my $watcher (@watchers) {
        $csv->print($fh, [$watcher->{name}, $watcher->{email}, $watcher->{phone}, $watcher->{subjectKeyword}, $watcher->{bodyKeyword}]);
    }

    close $fh;
    writeLog("Watchers written to csv file successfully");
}

#write a sub that reads watcher data from a csv file named "watchers.csv"
sub load_watchers_from_csv {
    writeLog("Loading watchers from csv file...");
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
        print "Name: " . $watcher->{name} . "\n";
        print "Email: " . $watcher->{email} . "\n";
        print "Phone: " . $watcher->{phone} . "\n";
        print "Subject Keyword: " . $watcher->{subjectKeyword} . "\n";
        print "Body Keyword: " . $watcher->{bodyKeyword} . "\n";
        push @watchers, $watcher;

        writeLog("-------------------------------------------------");
        writeLog("Watcher Loaded:");
        writeLog("Name: " . $watcher->{name});
        writeLog("Email: " . $watcher->{email});
        writeLog("Phone: " . $watcher->{phone});
        writeLog("Subject Keyword: " . $watcher->{subjectKeyword});
        writeLog("Body Keyword: " . $watcher->{bodyKeyword});
    }
    writeLog("Watchers loaded from csv file successfully");
}


sub checkWatchers {
my $messageType = shift;
my $messageNumber = shift;
my $messageTypeName;

if ($messageType == 1) {
    $messageTypeName = "NAVADMIN";
} elsif ($messageType == 2) {
    $messageTypeName = "ALNAV";
} elsif ($messageType == 3) {
    $messageTypeName = "MARADMIN";
} elsif ($messageType == 4) {
    $messageTypeName = "ALMAR";
}

writeLog("Checking watchers for $messageTypeName message number $messageNumber...");
my $index = findMessageIndex($messageType, $messageNumber);


my $message;
my $subject;
my $date;
my $url;

if ($messageType == 1) {
    $message = $NavadminMessages[$index];
    $subject = $NavadminSubjects[$index];
    $date = $NavadminDates[$index];
    $url = $NavadminUrls[$index];
} elsif ($messageType == 2) {
    $message = $AlNavMessages[$index];
    $subject = $AlNavSubjects[$index];
    $date = $AlNavDates[$index];
    $url = $AlNavUrls[$index];
} elsif ($messageType == 3) {
    $message = $MaradminMessages[$index];
    $subject = $MaradminSubjects[$index];
    $date = $MaradminDates[$index];
    $url = $MaradminUrls[$index];
} elsif ($messageType == 4) {
    $message = $AlMarMessages[$index];
    $subject = $AlMarSubjects[$index];
    $date = $AlMarDates[$index];
    $url = $AlMarUrls[$index];
} else {
    print "Invalid message type: $messageType\n";
    writeLog("Invalid message type: $messageType");
    return;
}

my $body = extractTextFromUrl($url);

print "Checking watchers for $messageTypeName message number $messageNumber...\n";
print "There are " . scalar @watchers . " total watchers\n";

writeLog("Checking watchers for $messageTypeName message number $messageNumber...");
writeLog("There are " . scalar @watchers . " total watchers");

#print "Body: $body\n";

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

our @notificationEmails = ();
our @notificationIndexes = ();

#Iterate through each watcher
foreach my $watcher (@watchers) {
    my $matched = 0;
    my $matchedWatcher;
    #Check if the subject contains any of the watcher's subject keywords
    my $subjectKeyword = $watcher->{subjectKeyword} || "";
    #Check to ensure the keyword is not empty and that is is found in the subject
    if ($subjectKeyword !~ /^\s*$/ && $subject =~ /$subjectKeyword/i) {
        $matched = 1;
        $matchedWatcher = $watcher;
        print "Subject matched ($subjectKeyword) for watcher " . $watcher->{name} . "\n";
        writeLog("Subject matched ($subjectKeyword) for watcher " . $watcher->{name});
    }
    else {
        if ($subjectKeyword and $subjectKeyword ne "") {
            print "Subject did not match ($subjectKeyword) for watcher " . $watcher->{name} . "\n";
            writeLog("Subject did not match ($subjectKeyword) for watcher " . $watcher->{name});
        } else {
            print "No subject keyword for watcher: " . $watcher->{name} . "\n";
            writeLog("No subject keyword for watcher: " . $watcher->{name});
        }
    }
    #Check if the body contains the watcher's body keyword in its entirety
    my $bodyKeyword = $watcher->{bodyKeyword} || "";
    if ($bodyKeyword !~ /^\s*$/ && $body =~ /\b$bodyKeyword\b/i) {
        $matched += 2;
        $matchedWatcher = $watcher;
        print "Body matched ($bodyKeyword) for watcher " . $watcher->{name} . "\n";
        writeLog("Body matched ($bodyKeyword) for watcher " . $watcher->{name});
    } else {
        if ($bodyKeyword and $bodyKeyword ne "") {
            print "Body did not match ($bodyKeyword) for watcher " . $watcher->{name} . "\n";
            writeLog("Body did not match ($bodyKeyword) for watcher " . $watcher->{name});
        } else {
            print "No body keyword for watcher: " . $watcher->{name} . "\n";
            writeLog("No body keyword for watcher: " . $watcher->{name});
        }
    }

        my $matchedOn = "";
        if ($matched) {
        if ($matched == 1) {
            $matchedOn = "Subject";
        } elsif ($matched == 2) {
            $matchedOn = "Body";
        } elsif ($matched == 3) {
            $matchedOn = "Subject and Body";
        }

        my $selectedEmailAddress = $matchedWatcher->{email};
        my $selectedPhoneNumber = $matchedWatcher->{phone};

        my $subjectKeyword = $matchedWatcher->{subjectKeyword};
        my $bodyKeyword = $matchedWatcher->{bodyKeyword};

        #Print Matched Message Information
        print "-------------------------------------------------\n";
        print "Watcher: " . $matchedWatcher->{name} . " matched on $matchedOn\n";
        print "Watcher Email: " . $selectedEmailAddress . "\n";
        print "Watcher Phone: " . $matchedWatcher->{phone} . "\n";
        print "Watcher Subject Keyword: $subjectKeyword \n";
        print "Watcher Body Keyword: $bodyKeyword \n";
        print "-------------------------------------------------\n";

        writeLog("-------------------------------------------------");
        writeLog("Watcher: " . $matchedWatcher->{name} . " matched on $matchedOn");
        writeLog("Watcher Email: " . $selectedEmailAddress);
        writeLog("Watcher Phone: " . $matchedWatcher->{phone});
        writeLog("Watcher Subject Keyword: $subjectKeyword");
        writeLog("Watcher Body Keyword: $bodyKeyword");
        writeLog("-------------------------------------------------");

        my $matchedText;
        if ($matchedOn eq "Subject") {
            $matchedText = $subjectKeyword;
            #If there is a body keyword, skip to next watcher
            if ($bodyKeyword and $bodyKeyword ne "") {
                print "Partial match found (Subject($subjectKeyword), but no body($bodyKeyword)). Skipping to next watcher...\n";
                writeLog("Partial match found (Subject($subjectKeyword), but no Body($bodyKeyword)). Skipping to next watcher...");
                next;
            }
        } elsif ($matchedOn eq "Body") {
            $matchedText = $bodyKeyword;
            #If there is a subject keyword, skip to next watcher
            if ($subjectKeyword and $subjectKeyword ne "") {
                print "Partial match found (Body($bodyKeyword), but no Subject($subjectKeyword)). Skipping to next watcher...\n";
                writeLog("Partial match found (Body($bodyKeyword), but no Subject($subjectKeyword)). Skipping to next watcher...");
                next;
            }
        } elsif ($matchedOn eq "Subject and Body") {
            $matchedText = $subjectKeyword . " and " . $bodyKeyword;
        }

        my $openingStatement = "You are receiving this message because you have an active message watcher and it matched on the following criteria: $matchedText found in $matchedOn\n\nThe following keywords were matched: \nSubject Keyword: " . $subjectKeyword . "\nBody Keyword: " . $bodyKeyword . "\nThe following message was found:\n\n";

        my $finalMessage = $openingStatement . $body;

        
        my $alreadyNotified = 0;
        my $index = 0;
        #check if $selectedEmailAddress exists within @notificationEmails
        foreach my $email (@notificationEmails) {
            if ($email eq $selectedEmailAddress) {
                #Check if $messageNumber is equal to $notificationIndexes[$index]
                if ($messageNumber == $notificationIndexes[$index]) {
                    $alreadyNotified = 1;
                } 
            }
        }

        if (not $alreadyNotified) {
            push @notificationEmails, $selectedEmailAddress;
            push @notificationIndexes, $messageNumber;
            if ($selectedEmailAddress and $selectedEmailAddress ne "") {
                emailNotification($selectedEmailAddress, 'rgagnier06@gmail.com', 'noreply@navadminwatcher.com', "New $messageTypeName Message Found", $finalMessage);
            } else {
                print "No email address found for watcher " . $matchedWatcher->{name} . "\n";
                writeLog("No email address found for watcher " . $matchedWatcher->{name});
            }
        } else {
            print "Already notified " . $selectedEmailAddress . " for message number $messageNumber\n";
            writeLog("Already notified " . $selectedEmailAddress . " for message number $messageNumber");
        }
        
        #sleep for 1 second
        sleep 1;

    }

}
writeLog("Finished checking watchers for message number $messageNumber");
}

sub writeLog {
    my $message = shift;
    #append the date and time on the front of the message in the following format: [MM/DD/YYYY HH:MM:SS]
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $date = sprintf("%02d/%02d/%04d", $mon+1, $mday, $year+1900);
    my $time = sprintf("%02d:%02d:%02d", $hour, $min, $sec);
    $message = "[$date $time] " . $message;
    my $logDirectory = "logs";
    my $logFile = $logDirectory . "/log.txt";
    
    #check if the logs directory exists
    if (!-d $logDirectory) {
        #create the logs directory
        mkdir $logDirectory or die "Could not create directory '$logDirectory' $!";
    }
    
    #check if the log file exists
    if (!-e $logFile) {
        #create a new log file
        open(my $fh, '>', $logFile) or die "Could not open file '$logFile' $!";
        close $fh;
    }
    
    #write the log message to the log file
    open(my $fh, '>>', $logFile) or die "Could not open file '$logFile' $!";
    print $fh $message . "\n";
    close $fh;
}

#Write a sub that extracts the text from the provided url page and stores it in a variable called $body
sub extractTextFromUrl {
    my $url = shift;
    my $body = get($url);
    return $body;
}

sub emailNotification {
  
    my $to = shift;
    my $bcc = shift;
    my $from = shift;
    my $subject = shift;
    my $message = shift;


    my $msg = Email::Simple->create(
        #authenticate the smtp server with the username and password

        header => [
            From    => $from,
            To      => $to,
            Bcc       => $bcc,
            Subject  => $subject,
        ],
        body => $message,
    );

    my $transport = Email::Sender::Transport::SMTP->new({
        host => 'smtp.elasticemail.com',
        port => 2525,
        sasl_username => $emailUsername,
        sasl_password => $emailPassword,
    });


    #print debug statement showing the email message
    print "-------------------------------------------------\n";
    print "Email Message:\n";
    print "From: $from\n";
    print "To: $to\n";
    print "Bcc: $bcc\n";
    print "Subject: $subject\n";
    print "-------------------------------------------------\n";

    writeLog("-------------------------------------------------");
    writeLog("Email Message:");
    writeLog("From: $from");
    writeLog("To: $to");
    writeLog("Bcc: $bcc");
    writeLog("Subject: $subject");
    writeLog("-------------------------------------------------");


    sendmail($msg, { transport => $transport });
    print "Email Sent Successfully\n";
    writeLog("Email Sent Successfully");
}

sub smsNotification {
    my $to = shift;
    my $message = shift;

    my $sender = SMS::Send->new('Twilio',
        _accountsid => $smsUsername,
        _token => $smsPassword,
    );

    my $sent = $sender->send_sms(
        text => $message,
        to => $to,
        from => '+18339393114',
    );

    if ($sent) {
        print "SMS Sent Successfully\n";
        writeLog("SMS Sent Successfully");
    } else {
        print "SMS Failed to Send\n";
        writeLog("SMS Failed to Send");
    }

}


sub scanMessages {
    #check log file size
    checkLogFileSize();

    writeLog("Scanning for new messages...");
    print "-------------------------------------------------\n";
    writeLog("-------------------------------------------------");
    
    #clear all arrays
    @NavadminMessages = @NavadminSubjects = @NavadminDates = @NavadminUrls = ();
    @AlNavMessages = @AlNavSubjects = @AlNavDates = @AlNavUrls = ();
    @MaradminMessages = @MaradminSubjects = @MaradminDates = @MaradminUrls = ();
    @AlMarMessages = @AlMarSubjects = @AlMarDates = @AlMarUrls = ();

    #load state from csv file
    load_state_from_csv();

    #load NAVADMIN data from web
    refreshNavadminDataFromWeb();

    #load ALNAV data from web
    refreshAlnavDataFromWeb();

    refreshUpdateDateTime();

    #If new index > old index: There are new messages
    my $newHighestMessageNumber = highestMessageNumber(1);
    if ($newHighestMessageNumber > $NavadminActiveIndex) {
        #print statement showing there are new messages in red
        print "\e[31mThere are new NAVADMIN messages.\e[0m\n";
        print "Old highest NAVADMIN message index: $NavadminActiveIndex\n";
        print "New highest NAVADMIN message index: $newHighestMessageNumber\n";

        writeLog("There are new NAVADMIN messages.");
        writeLog("Old highest NAVADMIN message index: $NavadminActiveIndex");
        writeLog("New highest NAVADMIN message index: $newHighestMessageNumber");

        #Iterate through each of the new messages and print them in green
        foreach my $message (@NavadminMessages) {
            my $currentMessageNumber = messageNumber($message);
            if ($currentMessageNumber <= $NavadminActiveIndex) {
                next;
            }

            my $index = findMessageIndex(1, $currentMessageNumber);
            
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
            print "-------------------------------------------------\n";
            print "\e[32m New NAVADMIN found: $message || Subject: $subject || Date: $date || $url\e[0m\n";

            writeLog("-------------------------------------------------");
            writeLog("New NAVADMIN found: $message || Subject: $subject || Date: $date || $url");
            #Trigger other actions here for this new message
            checkWatchers(1, messageNumber($message));
        }


    } else {
        print "-------------------------------------------------\n";
        print "\e[32mThere are no new NAVADMIN messages!\e[0m\n";
        print "Old highest message index: $NavadminActiveIndex\n";
        print "New highest message index: $newHighestMessageNumber\n";

        writeLog("-------------------------------------------------");
        writeLog("There are no new NAVADMIN messages!");
        writeLog("Old highest message index: $NavadminActiveIndex");
        writeLog("New highest message index: $newHighestMessageNumber");
    }

    $newHighestMessageNumber = highestMessageNumber(2);
    if ($newHighestMessageNumber > $AlNavActiveIndex) {
        #print statement showing there are new messages in red
        print "\e[31mThere are new ALNAV messages.\e[0m\n";
        print "Old highest ALNAV message index: $AlNavActiveIndex\n";
        print "New highest ALNAV message index: $newHighestMessageNumber\n";

        writeLog("There are new ALNAV messages.");
        writeLog("Old highest ALNAV message index: $AlNavActiveIndex");
        writeLog("New highest ALNAV message index: $newHighestMessageNumber");

        #Iterate through each of the new messages and print them in green
        foreach my $message (@AlNavMessages) {
            my $currentMessageNumber = messageNumber($message);
            if ($currentMessageNumber <= $AlNavActiveIndex) {
                next;
            }

            my $index = findMessageIndex(2, $currentMessageNumber);
            
            my $subject = $AlNavSubjects[$index];
            my $date = $AlNavDates[$index];
            my $url = $AlNavUrls[$index];

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
            print "-------------------------------------------------\n";
            print "\e[32m New ALNAV found: $message || Subject: $subject || Date: $date || $url\e[0m\n";

            writeLog("-------------------------------------------------");
            writeLog("New ALNAV found: $message || Subject: $subject || Date: $date || $url");
            #Trigger other actions here for this new message
            checkWatchers(2, messageNumber($message));
        } 

    } else {
        print "-------------------------------------------------\n";
        print "\e[32mThere are no new ALNAV messages!\e[0m\n";
        print "Old highest message index: $AlNavActiveIndex\n";
        print "New highest message index: $newHighestMessageNumber\n";

        writeLog("-------------------------------------------------");
        writeLog("There are no new ALNAV messages!");
        writeLog("Old highest message index: $AlNavActiveIndex");
        writeLog("New highest message index: $newHighestMessageNumber");
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

    writeLog("Finished scanning for new messages");
} 

sub write_to_csv {
    writeLog("Writing NAVADMIN data to csv file...");
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
    writeLog("NAVADMIN data written to csv file successfully");
}

sub refreshNavadminDataFromCSV {
    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1, eol => "\n" });
    my $filename = "data.csv";
    writeLog("Refreshing NAVADMIN data from csv file: $filename...");
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
    writeLog("NAVADMIN data refreshed from csv file successfully");
}

#write a sub that writes application state data to a csv file named "state.csv" in the root directory
sub write_state_to_csv {
    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1, eol => "\n" });
    my $filename = "state.csv";
    writeLog("Writing application state to csv file: $filename...");
    open(my $fh, ">:encoding(utf8)", $filename) or die "Could not open '$filename' for writing: $!";

    # Write headers to CSV file
    $csv->print($fh, ["NAVADMIN Active Index", "ALNAV Active Index", "MARADMIN Active Index", "ALMAR Active Index", "Last Update Date", "Last Update Time"]);

    # Write data to CSV file
    $csv->print($fh, [$NavadminActiveIndex, $AlNavActiveIndex, $MaradminActiveIndex, $AlMarActiveIndex, $lastUpdateDate, $lastUpdateTime]);
    $csv->print($fh, []);

    close $fh;
    writeLog("Application state written to csv file successfully");
}

#write a sub that reads application state data from a csv file named "state.csv"
sub load_state_from_csv {
    writeLog("Loading application state from csv file...");
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
    writeLog("Application state loaded from csv file successfully");
}

#write a sub that loads email credentials (username and password) from a csv file named "creds.csv"
sub load_credentials_from_csv {
    writeLog("Loading email credentials from csv file...");
    print "-------------------------------------------------\n";
    writeLog("-------------------------------------------------");
    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1, eol => "\n" });
    my $filename = "creds.csv";

    unless (-e $filename) {
        warn "\e[31mFile '$filename' does not exist.\e[0m";
        return;
    }

    open(my $fh, "<:encoding(utf8)", $filename) or warn "\e[31mCould not open '$filename' for reading: $!\e[0m";

    # Read headers from CSV file
    my $headers = $csv->getline($fh);

    #Read data from CSV file
    my $row = $csv->getline($fh);
    $emailUsername = $row->[0];
    print "Email Username loaded...\n";
    writeLog("Email Username loaded...");
    $emailPassword = $row->[1];
    print "Email Password loaded...\n";
    writeLog("Email Password loaded...");

    #Read new line from CSV file
    $row = $csv->getline($fh);

    $smsUsername = $row->[0];
    print "SMS Username loaded...\n";
    writeLog("SMS Username loaded...");
    $smsPassword = $row->[1];
    print "SMS Password loaded...\n";
    writeLog("SMS Password loaded..."); 
    
    close $fh;
    writeLog("Email credentials loaded from csv file successfully");
}


#Extract the number before the forward slash in this example "252/23"
sub messageNumber {
    my $originalMessageNumber = shift;
    my $index = index($originalMessageNumber, "/");
    my $cleanMessageNumber = substr($originalMessageNumber, 0, $index);

    return $cleanMessageNumber;
    writeLog("Message number ($cleanMessageNumber) extracted successfully from $originalMessageNumber");
}

sub refreshUpdateDateTime {
    writeLog("Refreshing update date and time...");
    #set the current system date in the format "MM/DD/YYYY"
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $lastUpdateDate = sprintf("%02d/%02d/%04d", $mon+1, $mday, $year+1900);
    #print "Last Update Date: $lastUpdateDate\n";

    #set the current system time in the format "HH:MM:SS"
    $lastUpdateTime = sprintf("%02d:%02d:%02d", $hour, $min, $sec);
    #print "Last Update Time: $lastUpdateTime\n";
    writeLog("Update date and time refreshed successfully");
}

#Write a sub that retrieves the highest message number from the array in the messageNumber() format
sub highestMessageNumber {
    # 1 = NAVADMIN, 2 = ALNAV, 3 = MARADMIN, 4 = ALMAR
    my $messageType = shift;
    writeLog("Retrieving highest message number from message type: $messageType...");
    my $highestMessageNumber = 0;

    if ($messageType == 1) {
        foreach my $message (@NavadminMessages) {

            my $navadminNumber = messageNumber($message);

            if ($navadminNumber > $highestMessageNumber) {
                $highestMessageNumber = $navadminNumber;
            }
        }
        writeLog("Highest NAVADMIN message number retrieved successfully: $highestMessageNumber");
        return $highestMessageNumber;
    } elsif ($messageType == 2) {
        foreach my $message (@AlNavMessages) {

            my $alnavNumber = messageNumber($message);

            if ($alnavNumber > $highestMessageNumber) {
                $highestMessageNumber = $alnavNumber;
            }
        }
        writeLog("Highest ALNAV message number retrieved successfully: $highestMessageNumber");
        return $highestMessageNumber;
    } elsif ($messageType == 3) {
        foreach my $message (@MaradminMessages) {

            my $maradminNumber = messageNumber($message);

            if ($maradminNumber > $highestMessageNumber) {
                $highestMessageNumber = $maradminNumber;
            }
        }
        writeLog("Highest MARADMIN message number retrieved successfully: $highestMessageNumber");
        return $highestMessageNumber;
    } elsif ($messageType == 4) {
        foreach my $message (@AlMarMessages) {

            my $almarNumber = messageNumber($message);

            if ($almarNumber > $highestMessageNumber) {
                $highestMessageNumber = $almarNumber;
            }
        }
        writeLog("Highest ALMAR message number retrieved successfully: $highestMessageNumber");
        return $highestMessageNumber;
    } else {
        print "Invalid message type ($messageType)\n";
        writeLog("Invalid message type ($messageType)");
    }
}

sub refreshNavadminDataFromWeb {
    writeLog("Refreshing NAVADMIN data from web...");

    # Get the HTML content of the URL
    my $html_content = get($NavadminUrl);

    # Create a new HTML::TableExtract object
    my $te = HTML::TableExtract->new( headers => [qw(Message Subject Date)] );

    # Parse the HTML content and extract the table data
    $te->parse($html_content);

    # Get the first table found
    my $table = $te->first_table_found;


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
    writeLog("Found " . scalar @NavadminMessages . " total NAVADMIN messages");

    #print a debug statement showing the number of urls found
    #print "Found " . scalar @NavadminUrls . " urls\n";
    writeLog("NAVADMIN data refreshed from web successfully");
}

sub refreshAlnavDataFromWeb {
    writeLog("Refreshing ALNAV data from web...");

    # Get the HTML content of the URL
    my $html_content = get($AlNavUrl);

    # Create a new HTML::TableExtract object
    my $te = HTML::TableExtract->new( headers => [qw(Message Subject Date)] );

    # Parse the HTML content and extract the table data
    $te->parse($html_content);

    # Get the first table found
    my $table = $te->first_table_found;

    # Remove any instances of "á" in the table
    $table =~ s/á//g;

    # Ensure there are no more than 1 space between words
    $table =~ s/\s+/ /g;

    #Remove any new lines in the table
    $table =~ s/\n//g;

    #Clear the arrays
    @AlNavMessages = ();
    @AlNavSubjects = ();
    @AlNavDates = ();
    @AlNavUrls = ();

    # Loop through each row of the table and store the data in the arrays
    foreach my $row ($table->rows) {
        push @AlNavMessages, $row->[0];
        push @AlNavSubjects, $row->[1];
        push @AlNavDates, $row->[2];
    }
    # Extract all hrefs that include "/Portals/55/Messages/ALNAV/ALN$currentYear" in the URL
    @AlNavUrls = $html_content =~ /href="(.*?\/Portals\/55\/Messages\/ALNAV\/ALN$currentYear.*?)"/g;
    
    #append each @url value with $baseNavyUrl
    foreach my $AlNavUrl (@AlNavUrls) {
        $AlNavUrl = $baseNavyUrl . $AlNavUrl;
    }

    #Reverse the order of the arrays
    @AlNavMessages = reverse @AlNavMessages;
    @AlNavSubjects = reverse @AlNavSubjects;
    @AlNavDates = reverse @AlNavDates;
    @AlNavUrls = reverse @AlNavUrls;

    #Print a debug statement showing the number of messages found
    print "Found " . scalar @AlNavMessages . " total ALNAV messages\n";
    writeLog("Found " . scalar @AlNavMessages . " total ALNAV messages");

    writeLog("ALNAV data refreshed from web successfully");
}

#Write a sub that is provided the message number and returns the index of the array that contains the message
sub findMessageIndex {
    my $messageType = shift;
    my $messageNumber = shift;
    my $index = 0;
    my @targetArray;
    if ($messageType == 1) { #NAVADMIN
        @targetArray = @NavadminMessages;
    } elsif ($messageType == 2) { #ALNAV
        @targetArray = @AlNavMessages;
    } elsif ($messageType == 3) { #MARADMIN
        @targetArray = @MaradminMessages;
    } elsif ($messageType == 4) { #ALMAR
        @targetArray = @AlMarMessages;
    } else {
        print "Invalid message type: $messageType\n";
        writeLog("Invalid message type: $messageType");
    }

    foreach my $message (@targetArray) {
        if (messageNumber($message) == $messageNumber) {
            return $index;
        }
        $index++;
    }

    return -1;
}

sub displayNavadminMessages {
    writeLog("Displaying NAVADMIN messages...");
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
        writeLog($index + 1 . ") Message: $message || " . "Subject: " . $NavadminSubjects[$index] . " || Date: " . $NavadminDates[$index] . " || " . $NavadminUrls[$index]);
        $index++;
    }
}

END {
  # perform any necessary cleanup
  writeLog("Performing cleanup...");
  writeLog("Writing watchers to csv file...");
  write_watchers_to_csv();
}