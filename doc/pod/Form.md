# NAME

Osiris::Form

# SYNOPSIS

    my $form = Osiris::Form->new(
        xml => $xml_file
    ) || do {
        $log->error("Init form failed");
        return undef;
    };

    $form->parse || do {
        $log->error("Form parse failed");
        return undef;
    };

    my $groups = $form->groups;
    my $guards = $form->guards;

# DESCRIPTION

Class for parsing ISIS forms - used both on the App and Job pages.

# API

Here is how the Isis application XML for a program is represented as
a Perl data structure in an Osiris::Form object:

    form = ARRAYREF of groups:
        { 
            name => GROUPNAME
            parameters => ARRAYREF of parameters:
                [
                    {
                        name        => NAME
                        field_type  => FIELD_TYPE
                        type        => DATA_TYPE
                        description => DESCRIPTION
                        default     => DEFAULT
                        ... (more) ...
                    },                  
                    ...
                ]
        }
        ...

FIELD\_TYPE is one of text\_field
                     textarea\_field
                     list\_field
                     boolean\_field
                     input\_file\_field 
                     output\_file\_field

TYPE is one of string/integer/double/boolean

Note that textarea\_fields are not in the Isis XML but I've added them
to support textareas in the additional metadata fields.

# METHODS

- new(xml => $xml)

    Create an Osiris::Form.  If the xml file is missing, returns undef.

- description()

    Returns the program description

- groups()

    Returns an arrayref of parameter groups.  This is the way the Dancer
    code gets the form definition which is rendered in the form.tt view.

- params()

    Returns an array of the names of all of the form parameters.

- input\_params()

    Returns an array of the names of all of the file input parameters.

- output\_params()

    Returns an array of the names of all of the file output parameters.

- \_aref()

    Utility method to de-reference arrayrefs and return arrays. 

- param(param => $paramnane)

    Return a parameter as a data structure (see API above)

- guards()

    Returns the form's guards as a hashref.  The guards are a set of value
    constraints on each parameter, as follows

    - file - one or more filename filters (\*.ext)
    - text - constraints on text fields: int|double|string
    - mandatory - Perltruthy, is this field mandatory
    - range - constrain numeric values
    - inclusions - make other fields mandatory based on values in this field
    - exclusions - make other fields forbidden based on values in this field

- parse()

    Parses the XML file.  On success, returns the entire form API as a hashref
    with the following members:

    - groups - arrayref of parameter groups
    - files - hashref of file fields
    - guards - hashref of parameter guards

    The hashref is also stored internally as {api}.

- xml\_field($elt)

    Copy an element's inner\_xml into the api using its tagname as
    the field name

- xml\_category($elt)

    Parses the <category> element

- xml\_group($elt)

    Parses a <group> element.  Each app has a <groups> element,
    containing one or more <group>s, each of which has one or more
    <parameters>.  This routine calls xml\_parameter on each of the
    child parameters, stores it in a group hashref, then appends
    the group hashref to {groups}

- xml\_parameter($elt)

    Top-level method for parsing parameters - the more complicated
    child elements are farmed out to their own methods.

    NOTE: in the ISIS schema, the tags default, greaterThan,
    lessThan and notEqual contain one or more <item> tags, within
    which are the actual values.  In the current release, there are
    no apps which have more than one <item> tag in any of these 
    elements, so this code just grabs the first item.

- xml\_minimax($elt)

    Parse a <minimum> or <maximum> element

- xml\_list($elt)

    Parse a <list> element, which gives a list with options and other
    fiddle

- xml\_helpers($elt)

    Parse a <helpers> element, which holds 1+ helper functions

- xml\_fix\_boolean(raw => $bool)
	

    Standardise the boolean values found in the XML to either
    'true' or 'false'

- make\_guard(parameter => $p)

    Takes one of the parameter hashes from the API and returns the guards
    for this as a Perl data structure.

    To fetch an app's guards as a hash by parameter, call $app->guards().

    Conversion to JSON used to be done here but now it's left to the
    Dancer framework

- \_make\_input\_filter\_re(filter => '\*.cub')

    Turns the content of a <filter> tag in the XML API and converts it
    to a Javascript regexp, for eg:

        *.cub *.QUB

        \.(cub|QUB)$



- \_split\_extensions\_filter

    Splits a filter value like "\*.cub \*.qub" and returns an arrayref normalised
    for case (so \*.txt and \*.TXT get merged)

- \_filter\_to\_exts(filter => $filter)

    Takes a filter value like '\*.txt \*.TXT \*.prt' and returns a case-normalised
    array of extensions like \[ 'prt', 'txt' \]
