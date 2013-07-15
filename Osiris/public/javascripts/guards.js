// Guards code

// bind_guards(guards) - takes an array of guards settings by parameter
// name and bind them to the form fields' onChange event

function bind_guards(param, guards) {
    var id = "#field_" + param
    $(id).data("guards", guards);
    console.log("Bound guards to " + id);
    $(id).change(apply_guards);
}

function apply_guards(event) {
    var val = this.value;
    var p = this.name
    var g = $(this).data("guards");
    var errors = [];

    console.log("Applying guards to " + p);
    console.log("Guards = " + g);
    if( !g ) {
        console.log("No guards");
        return 1;
    }

    if( g.mandatory ) {
        console.log("mandatory");
        if( !val ) {
            errors.push("Input must have a value");
        }
    }
    // store the errors array against the input element
    $(this).data('errors', errors);
    console.log("errors = " + errors.join(', '))
    if( errors.length > 0 ) {
        show_errors(p, this);
    } else {
        hide_errors(p, this);
    }
}



function show_errors(param, elt) {
    $(elt).addClass("error_highlight");
    $(elt).parent().addClass("error_highlight");
    var errors = $(elt).data('errors');
    var error_div = $("#error_" + param);
    error_div.empty();
    for ( var i = 0; i < errors.length; i++ ) {
        error_div.append('<span>' + errors[i] + '</span>');
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

    
