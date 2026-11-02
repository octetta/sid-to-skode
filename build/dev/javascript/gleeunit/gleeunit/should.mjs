import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { None, Some } from "../../gleam_stdlib/gleam/option.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import {
  Ok,
  Error,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  makeError,
  isEqual,
} from "../gleam.mjs";

const FILEPATH = "src/gleeunit/should.gleam";

export function equal(a, b) {
  let $ = isEqual(a, b);
  if ($) {
    return undefined;
  } else {
    throw makeError(
      "panic",
      FILEPATH,
      "gleeunit/should",
      10,
      "equal",
      $string.concat(
        listPrepend(
          "\n",
          listPrepend(
            $string.inspect(a),
            listPrepend(
              "\nshould equal\n",
              listPrepend($string.inspect(b), $List$Empty$const),
            ),
          ),
        ),
      ),
      {}
    )
  }
}

export function not_equal(a, b) {
  let $ = !isEqual(a, b);
  if ($) {
    return undefined;
  } else {
    throw makeError(
      "panic",
      FILEPATH,
      "gleeunit/should",
      23,
      "not_equal",
      $string.concat(
        listPrepend(
          "\n",
          listPrepend(
            $string.inspect(a),
            listPrepend(
              "\nshould not equal\n",
              listPrepend($string.inspect(b), $List$Empty$const),
            ),
          ),
        ),
      ),
      {}
    )
  }
}

export function be_ok(a) {
  if (a instanceof Ok) {
    let value = a[0];
    return value;
  } else {
    throw makeError(
      "panic",
      FILEPATH,
      "gleeunit/should",
      35,
      "be_ok",
      $string.concat(
        listPrepend(
          "\n",
          listPrepend(
            $string.inspect(a),
            listPrepend("\nshould be ok", $List$Empty$const),
          ),
        ),
      ),
      {}
    )
  }
}

export function be_error(a) {
  if (a instanceof Error) {
    let error = a[0];
    return error;
  } else {
    throw makeError(
      "panic",
      FILEPATH,
      "gleeunit/should",
      42,
      "be_error",
      $string.concat(
        listPrepend(
          "\n",
          listPrepend(
            $string.inspect(a),
            listPrepend("\nshould be error", $List$Empty$const),
          ),
        ),
      ),
      {}
    )
  }
}

export function be_some(a) {
  if (a instanceof Some) {
    let value = a[0];
    return value;
  } else {
    throw makeError(
      "panic",
      FILEPATH,
      "gleeunit/should",
      49,
      "be_some",
      $string.concat(
        listPrepend(
          "\n",
          listPrepend(
            $string.inspect(a),
            listPrepend("\nshould be some", $List$Empty$const),
          ),
        ),
      ),
      {}
    )
  }
}

export function be_none(a) {
  if (a instanceof None) {
    return undefined;
  } else {
    throw makeError(
      "panic",
      FILEPATH,
      "gleeunit/should",
      56,
      "be_none",
      $string.concat(
        listPrepend(
          "\n",
          listPrepend(
            $string.inspect(a),
            listPrepend("\nshould be none", $List$Empty$const),
          ),
        ),
      ),
      {}
    )
  }
}

export function be_true(actual) {
  let _pipe = actual;
  return equal(_pipe, true);
}

export function be_false(actual) {
  let _pipe = actual;
  return equal(_pipe, false);
}

export function fail() {
  return be_true(false);
}
