// Guards code

// bind_guards(guards) - takes an array of guards settings by parameter
// name and bind them to the form fields' onChange event

function bind_guards(param, guards) {
    var id = "#field_" + param
    var input_elt = $(id);
    $(id).data("guards", guards);
    $(id).focusout(function(e) { apply_guards(this)});
    $(id).change(function(e) { apply_guards(this)});
    $('#isisapp').submit(function(event) {
        return apply_all_guards(this);
    } );
}

// shortcut to jquery for an input element by param name

function input(p) {
    var s = "input[name=" + p + "]";
    var elt = $(s);
    console.log(s + ": " + elt);
    return elt;
}


function guard_event(event) {
    apply_guards(this);
}


function apply_all_guards(form) {
    var valid = true;
    $('input').each(function() {
        if( !apply_guards(this.name) ) {
            valid = false;
        }
    });
    return valid;
}
        


function apply_guards(elt) {
    var p = elt.name;
    var val = elt.value;
    var g = $(elt).data("guards");

    if( !g ) {
        return true;
    }

    var error = run_guards(g, val);

    if( error != '' ) {
        show_error(elt, error);
        return false;
    } else {
        hide_error(elt);
        return true;
    }
}



function run_guards(g, val) {

    if( g.mandatory ) {
        if( val == "" ) {
            return "Must have a value.";
        }
    }

    if( g.filepattern ) {
        var re = new RegExp(g.filepattern, 'i');
        if( !val.match(re) ) {
            return "Filename must match " + g.label;
        }
    }

    if( g.type == 'integer' ) {
        if( ! is_integer(val) ) {
            return "Must be an integer.";
        }
    }

    if( g.type == 'double' ) {
        if( ! is_double(val) ) {
            return "Must be a number.";
        }
    }

    // inclusions and exclusions are based on two inputs: the value of
    // a pull-down list applies rules to a field param.  I'm going to
    // only display the error against the field param, so if this
    // param is the list, we call apply_guard on those fields that it
    // affects.

    if( g.inclusions ) {
        if( g.inclusions[val] ) {
            for( var i in g.inclusions[val] ) {
                apply_guards($("#field_" + g.inclusions[val][i])[0]);
            }
        }
    }

    if( g.exclusions ) {
        if( g.exclusions[val] ) {
            for( var i in g.exclusions[val] ) {
                var p1 = g.exclusions[val][i];
                apply_guards($("#field_" + g.exclusions[val][i])[0]);
            }
        }
    }


    if( g.included ) {
        for( var control in g.included ) {
            var cval = $("input[name=" + control + "]").val();
            if( g.included[control][cval] ) {
                if( val == "" ) {
                    return "Must have a value when " + control + "=" + cval;
                }
            }
        }
    }

    if( g.excluded ) {
        for( var control in g.excluded ) {
            var cval = $("input[name=" + control + "]").val();
            if( g.excluded[control][cval] ) {
                if( val != "" ) {
                    return "Must be empty if " + control + "=" + cval;
                }
            }
        }
    }
    return "";
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




function show_error(elt, error) {
    $(elt).addClass("error_highlight");
    var param = $(elt).attr('name');
    var error_div = $("#error_" + param);
    error_div.empty();
    error_div.append(error);
    error_div.show();
}


function hide_error(elt) {
    $(elt).removeClass("error_highlight");
    var param = $(elt).attr('name');
    var error_div = $("#error_" + param);
    error_div.hide();
    error_div.empty();
}

    
