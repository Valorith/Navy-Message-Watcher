use strict;
use warnings;
use LWP::Simple;
use HTML::TableExtract;

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
