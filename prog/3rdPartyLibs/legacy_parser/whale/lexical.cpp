
/* A lexical analyzer generated by Dolphin */

#include "lexical.h"
using namespace std;

const char *DolphinLexicalAnalyzer::dolphin_copyright_notice=
	"A lexical analyzer generated by Dolphin 0.2.3 (5 March, 2001).\n"
	"Dolphin is (C) Alexander Okhotin <whale@aha.ru>, 1999-2001.\n";

const int DolphinLexicalAnalyzer::alphabet_cardinality;
const int DolphinLexicalAnalyzer::number_of_symbol_classes;
const int DolphinLexicalAnalyzer::number_of_start_conditions;
const int DolphinLexicalAnalyzer::number_of_dfa_states;
const unsigned char DolphinLexicalAnalyzer::initial_dfa_state;
const int DolphinLexicalAnalyzer::size_of_table_of_lines;
const int DolphinLexicalAnalyzer::number_of_actions;

Whale::Terminal *DolphinLexicalAnalyzer::get_token()
{
	if(lexeme)
		clear_lexeme();
	
	unsigned char state=initial_dfa_state;
	int start_pos=0, accepting_pos=0, action_to_call=0;
	append=false;
	
	for(int pos=start_pos;; pos++)
	{
		bool eof_reached_right_now=false;
		
		int recognized_action=states[state].action_upon_accept[start_condition];
		
		if(buffer.size()==pos)
		{
			if(eof_reached)
				eof_reached_right_now=true;
			else
			{
				char c;
				input_stream.get(c);
				
				if(input_stream.eof())
				{
					eof_reached=true;
					eof_reached_right_now=true;
				}
				else
				{
					buffer.push_back(c);
				}
			}
		}
		
		if(eof_reached_right_now)
		{
			if(pos==start_pos)
			{
				if(lexeme==NULL)
				{
					number_of_characters_in_lexeme=0;
					lexeme=new char[1];
					lexeme[0]=0;
				}
				
				
	if(start_condition==CPP_CODE)
	{
		cout << "End of file encountered while reading code starting "
			<< "at line " << line() << " column " << column() << ".\n";
		set_start_condition(MAIN);
		return make_token<Whale::TerminalError>();
	}
	else
		return make_token<Whale::TerminalEOF>();

			}
		}
		else
		{
			unsigned int c=(unsigned int)buffer[pos];
			state=states[state].access_transition(symbol_to_symbol_class[c]);
		}
		
		if(recognized_action)
		{
			accepting_pos=pos;
			action_to_call=recognized_action;
		}
		
		if(!state || eof_reached_right_now)
		{
			if(action_to_call==0)	// if it is a lexical error,
				accepting_pos=start_pos+1; // then eat one character.
			
			if(lexeme)
				delete lexeme;
			number_of_characters_in_lexeme=accepting_pos;
			lexeme=new char[number_of_characters_in_lexeme+1];
			copy(buffer.begin(), buffer.begin()+number_of_characters_in_lexeme, lexeme);
			lexeme[number_of_characters_in_lexeme]=0;
			
			switch(action_to_call)
			{
			case 0:
				
	if(start_condition==CPP_CODE)
		cout << "Lexical error in code starting at line " << line()
			<< " column " << column() << ".\n";
	else
		cout << "Lexical error at line " << line()
			<< " column " << column() << ".\n";
	
	return make_token<Whale::TerminalError>();

				break;
			case 1:
				 
				break;
			case 4:
				return make_token<Whale::TerminalKwTerminal>();
			case 5:
				return make_token<Whale::TerminalKwNonterminal>();
			case 6:
				return make_token<Whale::TerminalKwExternal>();
			case 7:
				return make_token<Whale::TerminalKwClass>();
			case 8:
				return make_token<Whale::TerminalKwNothing>();
			case 9:
				return make_token<Whale::TerminalKwTrue>();
			case 10:
				return make_token<Whale::TerminalKwFalse>();
			case 11:
				return make_token<Whale::TerminalE>();
			case 12:
				return make_token<Whale::TerminalKwIterationPair>();
			case 13:
				return make_token<Whale::TerminalKwCreate>();
			case 14:
				return make_token<Whale::TerminalKwUpdate>();
			case 15:
				return make_token<Whale::TerminalKwConnectUp>();
			case 16:
				return make_token<Whale::TerminalKwPrecedence>();
			case 17:
				return make_token<Whale::TerminalArrow>();
			case 18:
				return make_token<Whale::TerminalSemicolon>();
			case 19:
				return make_token<Whale::TerminalColon>();
			case 20:
				return make_token<Whale::TerminalScope>();
			case 21:
				return make_token<Whale::TerminalComma>();
			case 22:
				return make_token<Whale::TerminalOr>();
			case 23:
				return make_token<Whale::TerminalAnd>();
			case 24:
				return make_token<Whale::TerminalNot>();
			case 25:
				return make_token<Whale::TerminalSlash>();
			case 26:
				return make_token<Whale::TerminalLessThan>();
			case 27:
				return make_token<Whale::TerminalGreaterThan>();
			case 28:
				return make_token<Whale::TerminalLessOrEqual>();
			case 29:
				return make_token<Whale::TerminalGreaterOrEqual>();
			case 30:
				return make_token<Whale::TerminalEqual>();
			case 31:
				return make_token<Whale::TerminalNotEqual>();
			case 32:
				return make_token<Whale::TerminalLeftParenthesis>();
			case 33:
				return make_token<Whale::TerminalRightParenthesis>();
			case 34:
				return make_token<Whale::TerminalLeftBracket>();
			case 35:
				return make_token<Whale::TerminalRightBracket>();
			case 36:
				return make_token<Whale::TerminalAsterisk>();
			case 37:
				return make_token<Whale::TerminalPlus>();
			case 38:
				return make_token<Whale::TerminalAssign>();
			case 39:
				return make_token<Whale::TerminalString>();
			case 40:
				
	cout << "Unterminated string at line " << line()
		<< " column " << column() << ".\n";

	return make_token<Whale::TerminalError>();

				break;
			case 41:
				return make_token<Whale::TerminalNumber>();
			case 42:
				return make_token<Whale::TerminalHexNumber>();
			case 43:
				return make_token<Whale::TerminalId>();
			case 44:
				return make_token<Whale::TerminalCode>();
			case 45:
				
	set_start_condition(CPP_CODE);
	brace_count=1;
	append=true;

				break;
			case 46:
				 brace_count++; append=true; 
				break;
			case 47:
				
	brace_count--;
	if(brace_count==0)
	{
		set_start_condition(MAIN);
		return make_token<Whale::TerminalCode>();
	}
	else
		append=true;

				break;
			case 48:
				 append=true; 
				break;
			}
			
			if(append)
				start_pos=number_of_characters_in_lexeme;
			else
			{
				clear_lexeme();
				start_pos=0;
			}
			
			pos=start_pos-1;
			state=initial_dfa_state;
			accepting_pos=0;
			action_to_call=0;
		}
	}
}

void DolphinLexicalAnalyzer::clear_lexeme()
{
	for(int i=0; i<number_of_characters_in_lexeme; i++)
		internal_position_counter(buffer[i]);
	
	buffer.erase(buffer.begin(), buffer.begin()+number_of_characters_in_lexeme);
	
	if(lexeme)
	{
		delete lexeme;
		lexeme=NULL;
	}
}

const unsigned char DolphinLexicalAnalyzer::table_of_lines[DolphinLexicalAnalyzer::size_of_table_of_lines]={
	  0,   0,  55,  55,  55,  55,  49,  55,  55, 155,  55,  55,
	 55,  55,  55,  54, 157,  18,  18,  55,  55,  55,  55,  55,
	 55,  18,  18,  55,  55,  55,  18,  18,  18,  18,  18,  18,
	 18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,
	 18,  18,   0,  55,   0,  55,  55,   0,   0,  55,  55,  55,
	 55,  49,  55,  55, 155,  55,  55,  55,  55,  55,  55, 157,
	 55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,
	 55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,
	 55,  55,  55,  55,  55,  55,  55,  55,  55,   0,  55,   0,
	 55,  55,   0, 152, 152, 152, 152, 152, 152, 152, 152, 152,
	152, 152, 168, 152, 152, 152, 152, 152, 152, 152, 152, 152,
	152, 152, 152, 152, 152, 152, 152, 152, 152, 152, 152, 152,
	152, 152, 152, 152, 152, 152, 152, 152, 152, 152, 152, 152,
	152, 152, 152, 152, 152, 152, 152, 152, 152,   0, 152, 169,
	169, 169, 169, 169, 169, 169, 169, 169, 169, 175, 169, 169,
	169, 169, 169, 169, 169, 169, 169, 169, 169, 176, 169, 169,
	169, 169, 169, 169, 169, 169, 169, 169, 169, 169, 169, 169,
	169, 169, 169, 169, 169, 169, 169, 169, 169, 169, 169, 169,
	169, 169, 169, 169,   0,   0,  55,  55,  55,  55,  49,  55,
	 55, 155,  55,  55,  55,  55,  55,  55, 157,  57,  57,  55,
	 55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,
	 55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,
	 55,  55,  55,  55,  53,  55,   0,  55,   0,  55,  55,   0,
	  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
	  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
	  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
	  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
	  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,  49,  49,
	 55,  49,  49,  49,  49,  49,  49,  49,  49,  49,  49,  49,
	 49,  49,  49,  49,  49,  49, 150,  49,  49,  49, 170,  49,
	 49,  49,  49,  49,  49,  49,  49,  49,  49,  49,  49,  49,
	 49,  49,  49,  49,  49,  49,  49,  49,  49,  49,  49,  49,
	  0,   0,  48,  48,  48,  48,  48,  48,  48,  48,  48,  48,
	 48, 151,  48,  48,  48,  48,  48,  48,  48,  48,  48,  48,
	 48,  48,  48,  48,  48,  48,  48,  48,  48,  48,  48,  48,
	 48,  48,  48,  48,  48,  48,  48,  48,  48,  48,  48,  48,
	 48,  48,  48,  48,  48,  48,  48,  48,   0,   0,  52,  52,
	 52,  52, 159,  52,  52, 172,  52,  52,  52,  52,  52,  52,
	156,  52,  52,  52,  52,  52,  52,  52, 161,  52,  52,  52,
	 52,  52,  52,  52,  52,  52,  52,  52,  52,  52,  52,  52,
	 52,  52,  52,  52,  52,  52,  52,  52,  52,  52, 178,  52,
	178,  52,  52,   0,   0, 158,  55, 158, 158, 158, 158, 158,
	158, 158, 158, 158, 158, 158, 158, 158, 158, 158, 158, 158,
	158, 158, 158, 165, 158, 158, 158, 158, 158, 158, 158, 158,
	158, 158, 158, 158, 158, 158, 158, 158, 158, 158, 158, 158,
	158, 158, 158, 158, 158, 158, 158, 158, 158, 158,   0,   0,
	  0,   0, 155, 155, 155, 155, 155,  55, 155, 155, 155, 155,
	155, 155, 155, 155, 155, 155, 155, 155, 155, 155, 167, 155,
	155, 155, 171, 155, 155, 155, 155, 155, 155, 155, 155, 155,
	155, 155, 155, 155, 155, 155, 155, 155, 155, 155, 155, 155,
	155, 155, 155, 155,   0,   0,   0, 178, 178, 159, 159,  52,
	159, 159, 159, 159, 159, 159, 159, 159, 159, 159, 159, 159,
	159, 159, 159, 159, 159, 173, 159, 159, 159, 177, 159, 159,
	159, 159, 159, 159, 159, 159, 159, 159, 159, 159, 159, 159,
	159, 159, 159, 159, 159, 159, 159, 159, 159, 159, 159, 178,
	  0,   0, 160,  52, 160, 160, 160, 160, 160, 160, 160, 160,
	160, 160, 160, 160, 160, 160, 160, 160, 160, 160, 160, 160,
	174, 160, 160, 160, 160, 160, 160, 160, 160, 160, 160, 160,
	160, 160, 160, 160, 160, 160, 160, 160, 160, 160, 160, 160,
	160, 160, 160, 160, 160, 160, 160,   0,   0, 178, 178, 172,
	172, 172, 172, 172,  52, 172, 172, 172, 172, 172, 172, 172,
	172, 172, 172, 172, 172, 172, 172, 179, 172, 172, 172, 180,
	172, 172, 172, 172, 172, 172, 172, 172, 172, 172, 172, 172,
	172, 172, 172, 172, 172, 172, 172, 172, 172, 172, 172, 172,
	172, 178,   0,   0, 178, 178, 178, 178, 178, 178, 178, 178,
	178, 178, 178, 178, 178, 178, 178, 178, 178, 178, 178, 178,
	178, 178, 181, 178, 178, 178, 178, 178, 178, 178, 178, 178,
	178, 178, 178, 178, 178, 178, 178, 178, 178, 178, 178, 178,
	178, 178, 178, 178, 178, 178, 178, 178, 178,   0,   0,   2,
	  2,   2,   3,   4,  55,   5,  56,   6,   7,   8,   9,  10,
	162,  11,  12,  57,  13,  14,  15,  16,  17, 163,  18,  18,
	 19,  55,  20,  18,  18, 114,  18,  21, 110,  18,  18, 130,
	 18,  18, 117,  18,  92,  18,  18,  94, 125,  18,  18,  22,
	 23,  24,  25,  55,   0,   0,   2,   2,   2,  55,  49,  55,
	 55, 155,  55,  55,  55,  55,  55,  55,  50,  55,  55,  55,
	 55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,
	 55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,
	 55,  55,  55,  55,  55,  55,   0,  55,   0,  55,  55,   0,
	  0,   0,   0,   4,   4,  27,   4,   4,   4,   4,   4,   4,
	  4,   4,   4,   4,   4,   4,   4,   4,   4,   4,   4,   4,
	  4,   4,   4, 153,   4,   4,   4,   4,   4,   4,   4,   4,
	  4,   4,   4,   4,   4,   4,   4,   4,   4,   4,   4,   4,
	  4,   4,   4,   4,   4,   0,   0,   0,  55,  55,  55,  55,
	  0,  55,  55,   0,  55,  55,  48,  55,  55,  55,  51,  55,
	 55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,
	 55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,
	 55,  55,  55,  55,  55,  55,  55,  55,   0,  55,   0,  55,
	 55,   0,   0,  55,  55,  55,  55,  49,  55,  55, 155,  55,
	 55,  55,  55,  55,  54, 157,  18,  18,  55,  55,  55,  55,
	 55,  55,  18,  18,  55,  55,  55,  18,  18,  18,  18,  18,
	 18,  18,  18,  18,  18,  18,  18,  18, 107,  18,  18,  18,
	 18, 115,  18,   0,  55,   0,  55,  55,   0,   0,  55,  55,
	 55,  55,  49,  55,  55, 155,  55,  55,  55,  55,  55,  55,
	157,  33,  33,  55,  55,  55,  55,  55,  55,  33,  55,  55,
	 55,  55,  55,  33,  33,  33,  33,  33,  55,  55,  55,  55,
	 55,  55,  55,  55,  55,  55,  55,  55,  55,  55,   0,  55,
	  0,  55,  55,   0,   0,  51,   2,  51,  51,  51,  51,  51,
	 51,  51,  51,  51,  51,  51,  51,  51,  51,  51,  51,  51,
	 51,  51,  51,  51,  51,  51,  51,  51,  51,  51,  51,  51,
	 51,  51,  51,  51,  51,  51,  51,  51,  51,  51,  51,  51,
	 51,  51,  51,  51,  51,  51,  51,  51,  51,  51,   0,   0,
	  0,   0,  56,  56,  56,  56,  56,  27,  56,  56,  56,  56,
	 56,  56,  56,  56,  56,  56,  56,  56,  56,  56,  56,  56,
	 56,  56, 154,  56,  56,  56,  56,  56,  56,  56,  56,  56,
	 56,  56,  56,  56,  56,  56,  56,  56,  56,  56,  56,  56,
	 56,  56,  56,  56,   0,   0,   0,  55,  55,  55,  55,  49,
	 55,  55, 155,  55,  55,  55,  55,  55,  54, 157,  18,  18,
	 55,  55,  55,  55,  55,  55,  18,  18,  55,  55,  55,  18,
	 18,  18,  18,  83,  18,  18,  18, 143,  18,  18,  18,  18,
	 18,  18,  18,  18,  18,  18,  18,   0,  55,   0,  55,  55,
	  0,   0,  55,  55,  55,  55,  49,  55,  55, 155,  55,  55,
	 55,  55,  55,  54, 157,  18,  18,  55,  55,  55,  55,  55,
	 55,  18,  18,  55,  55,  55,  18,  18,  18,  18,  93,  18,
	 18,  18,  18,  18,  18,  18,  18,  18, 131,  18,  18,  18,
	 18,  18,   0,  55,   0,  55,  55,   0,   0,  55,  55,  55,
	 55,  49,  55,  55, 155,  55,  55,  55,  55,  55,  54, 157,
	 18,  18,  55,  55,  55,  55,  55,  55,  18,  18,  55,  55,
	 55,  18,  18,  18,  18,  18,  18,  18,  18,  18, 113,  18,
	 18, 138,  18, 121,  18,  18,  18,  18,  18,   0,  55,   0,
	 55,  55,   0,   0,  55,  55,  55,  55,  49,  55,  55, 155,
	 55,  55,  55,  55,  55,  54, 157,  18,  18,  55,  55,  55,
	 55,  55,  55,  18,  18,  55,  55,  55,  18,  18,  18,  18,
	 18,  18,  18,  18,  18,  18,  18, 118,  18,  18,  18,  18,
	 74,  18,  18,  18,   0,  55,   0,  55,  55,   0,   0,   0,
	  0,   4,   4,   4,   4,   4,   4,   4,   4,   4,   4,   4,
	  4,   4,   4,   4,   4,   4,   4,   4,   4,   4,   4,   4,
	  4,   4,   4,   4,   4,   4,   4,   4,   4,   4,   4,   4,
	  4,   4,   4,   4,   4,   4,   4,   4,   4,   4,   4,   4,
	  4,   4,   4,   0,   0,   0,   0,   0,  56,  56,  56,  56,
	 56,  56,  56,  56,  56,  56,  56,  56,  56,  56,  56,  56,
	 56,  56,  56,  56,  56,  56,  56,  56,  56,  56,  56,  56,
	 56,  56,  56,  56,  56,  56,  56,  56,  56,  56,  56,  56,
	 56,  56,  56,  56,  56,  56,  56,  56,  56,  56,   0,   0,
	  0,  52,  52,  52,  52, 178,  52,  52, 178,  52,  52, 169,
	 52,  52,  52, 160,  52,  52,  52,  52,  52,  52,  52, 161,
	 52,  52,  52,  52,  52,  52,  52,  52,  52,  52,  52,  52,
	 52,  52,  52,  52,  52,  52,  52,  52,  52,  52,  52,  52,
	 52, 178,  52, 178,  52,  52,   0,   0,  55,  55,  55,  55,
	  0,  55,  55,   0,  55,  55, 152,  55,  55,  55, 158,  55,
	 55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,
	 55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,  55,
	 55,  55,  55,  55,  55,  55,  55,  55,   0,  55,   0,  55,
	 55,   0,   0,   0,   0,  49,  49,  49,  49,  49,  49,  49,
	 49,  49,  49,  49,  49,  49,  49,  49,  49,  49,  49,  49,
	 49,  49,  49,  49,  49,  49,  49,  49,  49,  49,  49,  49,
	 49,  49,  49,  49,  49,  49,  49,  49,  49,  49,  49,  49,
	 49,  49,  49,  49,  49,  49,  49,   0,   0,   0,   0,   0,
	155, 155, 155, 155, 155, 155, 155, 155, 155, 155, 155, 155,
	155, 155, 155, 155, 155, 155, 155, 155, 155, 155, 155, 155,
	155, 155, 155, 155, 155, 155, 155, 155, 155, 155, 155, 155,
	155, 155, 155, 155, 155, 155, 155, 155, 155, 155, 155, 155,
	155, 155,   0,   0,   0, 178, 178, 159, 159, 159, 159, 159,
	159, 159, 159, 159, 159, 159, 159, 159, 159, 159, 159, 159,
	159, 159, 159, 173, 159, 159, 159, 159, 159, 159, 159, 159,
	159, 159, 159, 159, 159, 159, 159, 159, 159, 159, 159, 159,
	159, 159, 159, 159, 159, 159, 159, 159, 159, 178,   0,   0,
	178, 178, 172, 172, 172, 172, 172, 172, 172, 172, 172, 172,
	172, 172, 172, 172, 172, 172, 172, 172, 172, 172, 179, 172,
	172, 172, 172, 172, 172, 172, 172, 172, 172, 172, 172, 172,
	172, 172, 172, 172, 172, 172, 172, 172, 172, 172, 172, 172,
	172, 172, 172, 172, 178
};

const DolphinLexicalAnalyzer::StateData DolphinLexicalAnalyzer::states[DolphinLexicalAnalyzer::number_of_dfa_states+1]={
	{ 0, 0, NULL, { 0, 0 } },
	{ -1, 0, table_of_lines+825, { 0, 0 } },
	{ -1, 0, table_of_lines+880, { 1, 48 } },
	{ 22, 26, table_of_lines+55, { 0, 48 } },
	{ -1, 0, table_of_lines+935, { 40, 0 } },
	{ -1, 0, table_of_lines+55, { 23, 48 } },
	{ -1, 0, table_of_lines+55, { 32, 48 } },
	{ -1, 0, table_of_lines+55, { 33, 48 } },
	{ -1, 0, table_of_lines+55, { 36, 48 } },
	{ -1, 0, table_of_lines+55, { 37, 48 } },
	{ -1, 0, table_of_lines+55, { 21, 48 } },
	{ -1, 0, table_of_lines+990, { 25, 0 } },
	{ -1, 0, table_of_lines+220, { 41, 48 } },
	{ 19, 29, table_of_lines+55, { 19, 48 } },
	{ -1, 0, table_of_lines+55, { 18, 48 } },
	{ 22, 30, table_of_lines+55, { 26, 48 } },
	{ 22, 31, table_of_lines+55, { 38, 48 } },
	{ 22, 32, table_of_lines+55, { 27, 48 } },
	{ -1, 0, table_of_lines, { 43, 48 } },
	{ -1, 0, table_of_lines+55, { 34, 48 } },
	{ -1, 0, table_of_lines+55, { 35, 48 } },
	{ -1, 0, table_of_lines+1045, { 11, 48 } },
	{ -1, 0, table_of_lines+275, { 45, 46 } },
	{ -1, 0, table_of_lines+55, { 22, 48 } },
	{ -1, 0, table_of_lines+275, { 0, 47 } },
	{ -1, 0, table_of_lines+55, { 24, 48 } },
	{ -1, 0, table_of_lines+55, { 31, 48 } },
	{ -1, 0, table_of_lines+55, { 39, 48 } },
	{ -1, 0, table_of_lines+55, { 17, 48 } },
	{ 22, 28, table_of_lines+55, { 20, 48 } },
	{ -1, 0, table_of_lines+55, { 28, 48 } },
	{ -1, 0, table_of_lines+55, { 30, 48 } },
	{ -1, 0, table_of_lines+55, { 29, 48 } },
	{ -1, 0, table_of_lines+1100, { 42, 48 } },
	{ 24, 145, table_of_lines+55, { 44, 48 } },
	{ -1, 0, table_of_lines, { 9, 48 } },
	{ -1, 0, table_of_lines+330, { 44, 0 } },
	{ -1, 0, table_of_lines, { 7, 48 } },
	{ -1, 0, table_of_lines, { 10, 48 } },
	{ -1, 0, table_of_lines, { 13, 48 } },
	{ -1, 0, table_of_lines, { 14, 48 } },
	{ -1, 0, table_of_lines, { 8, 48 } },
	{ -1, 0, table_of_lines, { 6, 48 } },
	{ -1, 0, table_of_lines, { 16, 48 } },
	{ -1, 0, table_of_lines, { 4, 48 } },
	{ -1, 0, table_of_lines, { 15, 48 } },
	{ -1, 0, table_of_lines, { 5, 48 } },
	{ -1, 0, table_of_lines, { 12, 48 } },
	{ -1, 0, table_of_lines+385, { 0, 0 } },
	{ 24, 49, table_of_lines+330, { 0, 0 } },
	{ -1, 0, table_of_lines+990, { 0, 0 } },
	{ -1, 0, table_of_lines+1155, { 0, 0 } },
	{ -1, 0, table_of_lines+440, { 0, 48 } },
	{ -1, 0, table_of_lines+1100, { 0, 48 } },
	{ -1, 0, table_of_lines, { 0, 48 } },
	{ -1, 0, table_of_lines+55, { 0, 48 } },
	{ -1, 0, table_of_lines+1210, { 40, 0 } },
	{ 48, 55, table_of_lines+220, { 41, 48 } },
	{ 34, 35, table_of_lines, { 43, 48 } },
	{ 34, 38, table_of_lines, { 43, 48 } },
	{ 34, 39, table_of_lines, { 43, 48 } },
	{ 34, 40, table_of_lines, { 43, 48 } },
	{ 34, 43, table_of_lines, { 43, 48 } },
	{ 32, 62, table_of_lines, { 43, 48 } },
	{ 36, 41, table_of_lines, { 43, 48 } },
	{ 39, 42, table_of_lines, { 43, 48 } },
	{ 31, 65, table_of_lines, { 43, 48 } },
	{ 39, 44, table_of_lines, { 43, 48 } },
	{ 31, 67, table_of_lines, { 43, 48 } },
	{ 39, 46, table_of_lines, { 43, 48 } },
	{ 31, 69, table_of_lines, { 43, 48 } },
	{ 41, 66, table_of_lines, { 43, 48 } },
	{ 41, 64, table_of_lines, { 43, 48 } },
	{ 38, 72, table_of_lines, { 43, 48 } },
	{ 37, 73, table_of_lines, { 43, 48 } },
	{ 41, 68, table_of_lines, { 43, 48 } },
	{ 38, 75, table_of_lines, { 43, 48 } },
	{ 40, 76, table_of_lines, { 43, 48 } },
	{ 41, 144, table_of_lines, { 43, 48 } },
	{ 41, 63, table_of_lines, { 43, 48 } },
	{ 34, 79, table_of_lines, { 43, 48 } },
	{ 33, 80, table_of_lines, { 43, 48 } },
	{ 34, 81, table_of_lines, { 43, 48 } },
	{ 32, 82, table_of_lines, { 43, 48 } },
	{ -1, 0, table_of_lines+1265, { 43, 48 } },
	{ 41, 70, table_of_lines, { 43, 48 } },
	{ 38, 85, table_of_lines, { 43, 48 } },
	{ 40, 86, table_of_lines, { 43, 48 } },
	{ 42, 78, table_of_lines, { 43, 48 } },
	{ 39, 88, table_of_lines, { 43, 48 } },
	{ 38, 89, table_of_lines, { 43, 48 } },
	{ 43, 45, table_of_lines, { 43, 48 } },
	{ 44, 84, table_of_lines, { 43, 48 } },
	{ 44, 77, table_of_lines, { 43, 48 } },
	{ -1, 0, table_of_lines+1320, { 43, 48 } },
	{ 44, 71, table_of_lines, { 43, 48 } },
	{ 34, 95, table_of_lines, { 43, 48 } },
	{ 44, 87, table_of_lines, { 43, 48 } },
	{ 34, 97, table_of_lines, { 43, 48 } },
	{ 44, 47, table_of_lines, { 43, 48 } },
	{ 38, 99, table_of_lines, { 43, 48 } },
	{ 31, 100, table_of_lines, { 43, 48 } },
	{ 43, 101, table_of_lines, { 43, 48 } },
	{ 30, 102, table_of_lines, { 43, 48 } },
	{ 41, 103, table_of_lines, { 43, 48 } },
	{ 42, 104, table_of_lines, { 43, 48 } },
	{ 38, 105, table_of_lines, { 43, 48 } },
	{ 45, 90, table_of_lines, { 43, 48 } },
	{ 45, 59, table_of_lines, { 43, 48 } },
	{ 39, 108, table_of_lines, { 43, 48 } },
	{ 31, 109, table_of_lines, { 43, 48 } },
	{ 45, 37, table_of_lines, { 43, 48 } },
	{ 45, 111, table_of_lines, { 43, 48 } },
	{ 31, 112, table_of_lines, { 43, 48 } },
	{ -1, 0, table_of_lines+1375, { 43, 48 } },
	{ 46, 96, table_of_lines, { 43, 48 } },
	{ -1, 0, table_of_lines+1430, { 43, 48 } },
	{ 42, 116, table_of_lines, { 43, 48 } },
	{ 46, 98, table_of_lines, { 43, 48 } },
	{ 46, 60, table_of_lines, { 43, 48 } },
	{ 31, 119, table_of_lines, { 43, 48 } },
	{ 34, 120, table_of_lines, { 43, 48 } },
	{ 46, 61, table_of_lines, { 43, 48 } },
	{ 31, 122, table_of_lines, { 43, 48 } },
	{ 33, 123, table_of_lines, { 43, 48 } },
	{ 43, 124, table_of_lines, { 43, 48 } },
	{ 46, 106, table_of_lines, { 43, 48 } },
	{ 31, 126, table_of_lines, { 43, 48 } },
	{ 44, 127, table_of_lines, { 43, 48 } },
	{ 34, 128, table_of_lines, { 43, 48 } },
	{ 46, 129, table_of_lines, { 43, 48 } },
	{ 47, 58, table_of_lines, { 43, 48 } },
	{ 47, 91, table_of_lines, { 43, 48 } },
	{ 30, 132, table_of_lines, { 43, 48 } },
	{ 46, 133, table_of_lines, { 43, 48 } },
	{ 32, 134, table_of_lines, { 43, 48 } },
	{ 34, 135, table_of_lines, { 43, 48 } },
	{ 41, 136, table_of_lines, { 43, 48 } },
	{ 41, 137, table_of_lines, { 43, 48 } },
	{ 49, 43, table_of_lines, { 43, 48 } },
	{ 46, 139, table_of_lines, { 43, 48 } },
	{ 38, 140, table_of_lines, { 43, 48 } },
	{ 44, 141, table_of_lines, { 43, 48 } },
	{ 42, 142, table_of_lines, { 43, 48 } },
	{ -1, 0, table_of_lines, { 11, 48 } },
	{ -1, 0, table_of_lines+55, { 44, 48 } },
	{ 24, 164, table_of_lines+110, { 44, 0 } },
	{ -1, 0, table_of_lines+495, { 44, 0 } },
	{ 24, 166, table_of_lines+275, { 44, 0 } },
	{ -1, 0, table_of_lines+550, { 44, 0 } },
	{ 24, 49, table_of_lines+330, { 44, 0 } },
	{ 16, 2, table_of_lines+385, { 0, 0 } },
	{ -1, 0, table_of_lines+110, { 0, 0 } },
	{ -1, 0, table_of_lines+1485, { 0, 0 } },
	{ -1, 0, table_of_lines+1540, { 0, 0 } },
	{ 24, 155, table_of_lines+550, { 0, 0 } },
	{ -1, 0, table_of_lines+1595, { 0, 0 } },
	{ -1, 0, table_of_lines+1650, { 0, 0 } },
	{ 24, 158, table_of_lines+495, { 0, 0 } },
	{ -1, 0, table_of_lines+605, { 0, 0 } },
	{ -1, 0, table_of_lines+660, { 0, 0 } },
	{ 24, 34, table_of_lines+440, { 0, 48 } },
	{ 23, 28, table_of_lines+55, { 0, 48 } },
	{ 24, 52, table_of_lines+55, { 0, 48 } },
	{ -1, 0, table_of_lines+110, { 44, 0 } },
	{ 24, 158, table_of_lines+495, { 44, 0 } },
	{ -1, 0, table_of_lines+275, { 44, 0 } },
	{ 24, 155, table_of_lines+550, { 44, 0 } },
	{ 16, 55, table_of_lines+110, { 0, 0 } },
	{ -1, 0, table_of_lines+165, { 0, 0 } },
	{ -1, 0, table_of_lines+1705, { 0, 0 } },
	{ -1, 0, table_of_lines+1760, { 0, 0 } },
	{ -1, 0, table_of_lines+715, { 0, 0 } },
	{ 24, 36, table_of_lines+605, { 0, 0 } },
	{ 24, 147, table_of_lines+660, { 0, 0 } },
	{ 16, 52, table_of_lines+165, { 0, 0 } },
	{ 24, 146, table_of_lines+165, { 0, 0 } },
	{ -1, 0, table_of_lines+1815, { 0, 0 } },
	{ -1, 0, table_of_lines+770, { 0, 0 } },
	{ 24, 149, table_of_lines+715, { 0, 0 } },
	{ -1, 0, table_of_lines+1870, { 0, 0 } },
	{ 24, 148, table_of_lines+770, { 0, 0 } }
};

const int DolphinLexicalAnalyzer::symbol_to_symbol_class[DolphinLexicalAnalyzer::alphabet_cardinality]={
	  0,   1,   1,   1,   1,   1,   1,   1,   1,   2,   3,   1,
	  1,   2,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,
	  1,   1,   1,   1,   1,   1,   1,   1,   4,   5,   6,   7,
	  7,   7,   8,   9,  10,  11,  12,  13,  14,  15,   7,  16,
	 17,  18,  18,  18,  18,  18,  18,  18,  18,  18,  19,  20,
	 21,  22,  23,   7,  24,  25,  25,  25,  25,  25,  25,  26,
	 26,  26,  26,  26,  26,  26,  26,  26,  26,  26,  26,  26,
	 26,  26,  26,  26,  26,  26,  26,  27,  28,  29,   7,  30,
	  7,  31,  25,  32,  33,  34,  35,  36,  37,  38,  26,  26,
	 39,  40,  41,  42,  43,  26,  44,  45,  46,  47,  26,  26,
	 48,  49,  26,  50,  51,  52,  53,   7,  54,  54,  54,  54,
	 54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,
	 54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,
	 54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,
	 54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,
	 54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,
	 54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,
	 54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,
	 54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,
	 54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,
	 54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,  54,
	 54,  54,  54,  54
};
