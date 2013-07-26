// transition helpers


function setup_help_transitions() {
    $(".paramhelp").on("click", toggle_description);
}

function toggle_description(event) {
    var desc = $(this).children(".paramdesc");
    if( desc.length > 0 ) {
        if( desc.is(":visible") ) {
            desc.slideUp();
        } else {
            desc.slideDown();
        }
    } else {
        console.log("jQuery selector empty");
    }
}

// appfile_select - called when the user chooses a previously used
// or created file via the file browser.

function appfile_select(param, job, file, type) {
    var fid = '#field_' + param + '_alt';

    var t = 'input';
    if( type ) {
        t = 'output';
    }

    var elt = $(fid);
    if( elt ) {
        elt.val(t + '/' + job + '/' + file);
    } else {
        console.log("No field with id = " + fid);
    }
}

    
