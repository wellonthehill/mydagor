// Copyright 2007-2010 Baptiste Lepilleur
// Distributed under MIT license, or public domain if desired and
// recognized in your jurisdiction.
// See file LICENSE for detail or copy at http://jsoncpp.sourceforge.net/LICENSE

#ifndef CPPTL_JSON_READER_H_INCLUDED
# define CPPTL_JSON_READER_H_INCLUDED

#if !defined(JSON_IS_AMALGAMATION)
# include "features.h"
# include "value.h"
#endif // if !defined(JSON_IS_AMALGAMATION)
# include <EASTL/string.h>
# include <EASTL/vector.h>

namespace Json
{
   /** \brief Unserialize a <a HREF="http://www.json.org">JSON</a> document into a Value.
    *
    */
   class JSON_API Reader
   {
   public:
      typedef char Char;
      typedef const Char *Location;

      /** \brief Constructs a Reader allowing all features
       * for parsing.
       */
      Reader();

      /** \brief Constructs a Reader allowing the specified feature set
       * for parsing.
       */
      Reader( const Features &features );

      /** \brief Read a Value from a <a HREF="http://www.json.org">JSON</a> document.
       * \param document UTF-8 encoded string containing the document to read.
       * \param root [out] Contains the root value of the document if it was
       *             successfully parsed.
       * \param collectComments \c true to collect comment and allow writing them back during
       *                        serialization, \c false to discard comments.
       *                        This parameter is ignored if Features::allowComments_
       *                        is \c false.
       * \return \c true if the document was successfully parsed, \c false if an error occurred.
       */
      bool parse( const eastl::string &document, 
                  Value &root,
                  bool collectComments = true );

      /** \brief Read a Value from a <a HREF="http://www.json.org">JSON</a> document.
       * \param beginDoc Pointer on the beginning of the UTF-8 encoded string of the document to read.
       * \param endDoc Pointer on the end of the UTF-8 encoded string of the document to read. 
       \               Must be >= beginDoc.
       * \param root [out] Contains the root value of the document if it was
       *             successfully parsed.
       * \param collectComments \c true to collect comment and allow writing them back during
       *                        serialization, \c false to discard comments.
       *                        This parameter is ignored if Features::allowComments_
       *                        is \c false.
       * \return \c true if the document was successfully parsed, \c false if an error occurred.
       */
      bool parse( const char *beginDoc, const char *endDoc, 
                  Value &root,
                  bool collectComments = true );

      /** \brief Returns a user friendly string that list errors in the parsed document.
       * \return Formatted error message with the list of errors with their location in 
       *         the parsed document. An empty string is returned if no error occurred
       *         during parsing.
       * \deprecated Use getFormattedErrorMessages() instead (typo fix).
       */
      JSONCPP_DEPRECATED("Use getFormattedErrorMessages instead") 
      eastl::string getFormatedErrorMessages() const;

      /** \brief Returns a user friendly string that list errors in the parsed document.
       * \return Formatted error message with the list of errors with their location in 
       *         the parsed document. An empty string is returned if no error occurred
       *         during parsing.
       */
      eastl::string getFormattedErrorMessages() const;

   private:
      enum TokenType
      {
         tokenEndOfStream = 0,
         tokenObjectBegin,
         tokenObjectEnd,
         tokenArrayBegin,
         tokenArrayEnd,
         tokenString,
         tokenNumber,
         tokenTrue,
         tokenFalse,
         tokenNull,
         tokenArraySeparator,
         tokenMemberSeparator,
         tokenComment,
         tokenError
      };

      class Token
      {
      public:
         TokenType type_;
         Location start_;
         Location end_;
      };

      class ErrorInfo
      {
      public:
         Token token_;
         eastl::string message_;
         Location extra_;
      };

      typedef eastl::vector<ErrorInfo> Errors;

      bool expectToken( TokenType type, Token &token, const char *message );
      bool readToken( Token &token );
      void skipSpaces();
      bool match( Location pattern, 
                  int patternLength );
      bool readComment();
      bool readCStyleComment();
      bool readCppStyleComment();
      bool readString();
      void readNumber();
      bool readValue();
      bool readObject( Token &token );
      bool readArray( Token &token );
      bool decodeNumber( Token &token );
      bool decodeString( Token &token );
      bool decodeString( Token &token, eastl::string &decoded );
      bool decodeDouble( Token &token );
      bool decodeUnicodeCodePoint( Token &token, 
                                   Location &current, 
                                   Location end, 
                                   unsigned int &unicode );
      bool decodeUnicodeEscapeSequence( Token &token, 
                                        Location &current, 
                                        Location end, 
                                        unsigned int &unicode );
      bool addError( const eastl::string &message, 
                     Token &token,
                     Location extra = 0 );
      bool recoverFromError( TokenType skipUntilToken );
      bool addErrorAndRecover( const eastl::string &message, 
                               Token &token,
                               TokenType skipUntilToken );
      void skipUntilSpace();
      Value &currentValue();
      Char getNextChar();
      void getLocationLineAndColumn( Location location,
                                     int &line,
                                     int &column ) const;
      eastl::string getLocationLineAndColumn( Location location ) const;
      void addComment( Location begin, 
                       Location end, 
                       CommentPlacement placement );
      void skipCommentTokens( Token &token );
   
      typedef eastl::vector<Value*> Nodes;
      Nodes nodes_;
      Errors errors_;
      eastl::string document_;
      Location begin_;
      Location end_;
      Location current_;
      Location lastValueEnd_;
      Value *lastValue_;
      eastl::string commentsBefore_;
      Features features_;
      bool collectComments_;
   };

} // namespace Json

#endif // CPPTL_JSON_READER_H_INCLUDED
