use strict;
use warnings;
use LWP::Simple;
use HTML::TableExtract;

#load data from csv file
load_from_csv();

#store the current year in a variable
my $year = (localtime)[5] + 1900;

our $baseUrl = "https://www.mynavyhr.navy.mil";

# URL to scrape
my $url = "$baseUrl/References/Messages/NAVADMIN-$year/";

# Get the HTML content of the URL
my $html_content = get($url);

# Create a new HTML::TableExtract object
my $te = HTML::TableExtract->new( headers => [qw(Message Subject Date)] );

# Parse the HTML content and extract the table data
$te->parse($html_content);

# Get the first table found
my $table = $te->first_table_found;

# Initialize the arrays
our @messages;
our @subjects;
our @dates;
our @urls;

# Initialize new arrays
our @newMessages;
our @newSubjects;
our @newDates;
our @newUrls;

#clear the arrays
@messages = ();
@subjects = ();
@dates = ();
@urls = ();

# Extract all hrefs that include "/Portals/55/Messages/NAVADMIN/NAV$year" in the URL
@urls = $html_content =~ /href="(.*?\/Portals\/55\/Messages\/NAVADMIN\/NAV$year.*?)"/g;

#append each @url value with $baseUrl
foreach my $url (@urls) {
    $url = $baseUrl . $url;
}

# Remove any instances of "á" in the table
$table =~ s/á//g;

# Ensure there are no more than 1 space between words
$table =~ s/\s+/ /g;

#Remove any new lines in the table
$table =~ s/\n//g;

# Loop through each row of the table and store the data in the arrays
foreach my $row ($table->rows) {
    push @messages, $row->[0];
    push @subjects, $row->[1];
    push @dates, $row->[2];
}

#Print a debug statement showing the number of messages found
print "Found " . scalar @messages . " messages\n";

#print a debug statement showing the number of urls found
print "Found " . scalar @urls . " urls\n";


my $messageCount = @messages;
my $newMessageCount = @newMessages;

#If new messages > old messages: There are new messages

if ($newMessageCount > $messageCount) {
    print "\e[32mThere are new messages!\e[0m\n";
    print "New messages: " . ($newMessageCount - $messageCount) . "\n";
    print "Old messages: $messageCount\n";

    #copy the new arrays to the old arrays
    @messages = @newMessages;
    @subjects = @newSubjects;
    @dates = @newDates;
    @urls = @newUrls;

} else {
    print "\e[31mThere are no new messages.\e[0m\n";
    print "New messages: $newMessageCount\n";
    print "Old messages: $messageCount\n";
}

my $index = 0;
foreach my $message (@messages) {

    # Remove any instances of "á" in the table
    $messages[$index] =~ s/á//g;
    $subjects[$index] =~ s/á//g;
    $dates[$index] =~ s/á//g;

    # Ensure there are no more than 1 space between words
    $messages[$index] =~ s/\s+/ /g;
    $subjects[$index] =~ s/\s+/ /g;
    $dates[$index] =~ s/\s+/ /g;

    #Remove any new lines in the table
    $messages[$index] =~ s/\n//g;
    $subjects[$index] =~ s/\n//g;
    $dates[$index] =~ s/\n//g;

    print $index + 1 . ") Message: $message || " . "Subject: " . $subjects[$index] . " || Date: " . $dates[$index] . " || " . $urls[$index] . "\n";
    $index++;
}

write_to_csv();

sub write_to_csv {
    use Text::CSV;

    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1, eol => "\n" });
    my $filename = "data.csv";

    open(my $fh, ">:encoding(utf8)", $filename) or die "Could not open '$filename' for writing: $!";

    # Write headers to CSV file
    $csv->print($fh, ["Message", "Subject", "Date", "URL"]);

    # Write data to CSV file
    for (my $i = 0; $i < scalar @messages; $i++) {
        $csv->print($fh, [$messages[$i], $subjects[$i], $dates[$i], $urls[$i]]);
    }

    close $fh;
}

sub load_from_csv {
    use Text::CSV;

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
    @newMessages = ();
    @newSubjects = ();
    @newDates = ();
    @newUrls = ();

    # Read data from CSV file
    while (my $row = $csv->getline($fh)) {
        push @newMessages, $row->[0];
        push @newSubjects, $row->[1];
        push @newDates, $row->[2];
        push @newUrls, $row->[3];
    }

    close $fh;

}