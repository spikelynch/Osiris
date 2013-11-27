# NAME

Osiris::App

# SYNOPSIS

    	my $app = Osiris::App->new(
		dir => $conf->{isisdir},
		app => $name,
		brief => $toc->{$name}
	);

    my $form = $app->read_form;

    my $params = $app->params;
    
    my $in_params = $app->input_params;

    my $out_params = $app->output_params;





# DESCRIPTION

A class representing an Isis app.  Uses Osiris::Form to parse the XML for
the web form API.



# METHODS

- new(%params)
    - app: the application's command name
    - dir: the Isis base directory
    - brief: the brief description from the TOC file

    Creates a new Osiris::App object, populating it with the command name (app)
    and the brief description.

    This is done at startup by the Dancer app in the method Osiris::load\_toc,
    which parses the Isis table of contents XML file.

- read\_form()

    Ensure that the form has been parsed, and return the Osiris::Form
    object. Returns undef if the parse fails.

- name()

    Return the app's name

- brief() 

    Return the app's brief description

- description() 

    Return the app's full description, which may contain HTML

- form()

    Parses the form, and returns a data structure which can be used to fill 
    out the form.tt template. This is not the Osiris::Form object, but the
    return value of Osiris::Form->groups - see Osiris::Form for more details.

- params

    Return a list of all the app's parameters

- input\_params

    Return a list of all of the app's file upload parameters

- output\_params

    Returns a list of all of this app's output file parameter names

- param(param => $p)

    Return the API settings for a parameter as a hashref

- guards()

    Returns all this form's guards as a hashref-by-parameter name which can
    be passed into the form templates and javascript guards.

    See Osiris::Form::guards for details.
