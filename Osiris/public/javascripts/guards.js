// Guards code

// bind_guards(guards) - takes an array of guards settings by parameter
// name and bind them to the form fields' onChange event

function bind_guards(param, guards) {
    var id = "#field_" + param
    var input_elt = $(id);
    input_elt.data("guards", guards);
    input_elt.focusout(function(e) { apply_guards(this)});
    input_elt.change(function(e) { apply_guards(this)});
    $('#isisapp').submit(function(event) {
//        event.preventDefault();
        console.log("Applying guards");
        return apply_all_guards(this);
    } );
}


function guard_event(event) {
    apply_guards(this);
}


function apply_all_guards(form) {
    var valid = true;
    $('input').each(function() {
        if( !apply_guards(this) ) {
            valid = false;
        }
    });
    return valid;
}
        


function apply_guards(elt) {
    var val = elt.value;
    var p = elt.name
    var g = $(elt).data("guards");
    var errors = [];

 
    if( !g ) {
         return 1;
    }

    if( g.mandatory ) {
        if( val == "" ) {
            errors.push("This parameter must have a value.");
        }
    }

    if( g.filepattern ) {
        console.log("Applying file filter " + g.filepattern);
        var re = new RegExp(g.filepattern, 'i');
        if( !val.match(re) ) {
            errors.push("The filename must match " + g.label);
        }
    }

    if( g.type == 'integer' ) {
        if( ! is_integer(val) ) {
            errors.push("This parameter must be an integer.");
        }
    }

    if( g.type == 'double' ) {
        if( ! is_double(val) ) {
            errors.push("This parameter must be a number.");
        }
    }


    // store the errors array against the input element
    $(elt).data('errors', errors);
    console.log("errors = " + errors.join(', '))
    if( errors.length > 0 ) {
        show_errors(p, elt);
        return false;
    } else {
        hide_errors(p, elt);
        return true;
    }
}



function is_integer(v) {
    var parsed = parseInt(v, 10);
    if( !isNaN(v) && v == parsed ){
        return 1;
    }
    return 0;
}

function is_double(v) {
    var parsed = parseFloat(v);
    if( !isNaN(v) && v == parsed ) {
        return 1;
    }
    return 0;
}











function show_errors(param, elt) {
    $(elt).addClass("error_highlight");
    var errors = $(elt).data('errors');
    var error_div = $("#error_" + param);
    error_div.empty();
    for ( var i = 0; i < errors.length; i++ ) {
        error_div.append('<p class="error">' + errors[i] + '</p>');
    }
    error_div.show();
}


function hide_errors(param, elt) {
    $(elt).removeClass("error_highlight");
    $(elt).parent().removeClass("error_highlight");
    var error_div = $("#error_" + param);
    error_div.hide();
    error_div.empty();
}

    
